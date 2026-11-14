import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "de.sonnenschein.app", category: "Computation")

actor SolarComputationService {
    private var engine: ShadowEngine?
    private var store: GeometryStore?
    private(set) var isReady = false

    private static let berlinTZ = TimeZone(identifier: "Europe/Berlin")!
    private static let observerHeight = 1.2

    // Coverage bounds for PLZ 10961 (approximate bounding box)
    private static let minLat = 52.480
    private static let maxLat = 52.510
    private static let minLon = 13.375
    private static let maxLon = 13.430

    func loadData() {
        guard !isReady else { return }
        let start = CFAbsoluteTimeGetCurrent()

        guard let asset = NSDataAsset(name: "TurandotBuildings") else {
            logger.error("Geodaten-Datei nicht im Bundle gefunden")
            return
        }

        do {
            let loadedStore = try GeometryStore.load(from: asset.data)
            self.store = loadedStore
            self.engine = ShadowEngine(store: loadedStore)
            self.isReady = true
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            logger.info("Geodaten geladen: \(loadedStore.buildings.count) Gebäude in \(elapsed, format: .fixed(precision: 0)) ms")
        } catch {
            logger.error("Fehler beim Laden der Geodaten: \(error.localizedDescription)")
        }
    }

    func evaluate(lat: Double, lon: Double, at date: Date) throws -> PointResult {
        guard let engine, let store, isReady else {
            throw ComputationError.engineNotReady
        }

        let start = CFAbsoluteTimeGetCurrent()

        // Check coverage
        guard lat >= Self.minLat && lat <= Self.maxLat && lon >= Self.minLon && lon <= Self.maxLon else {
            throw ComputationError.outsideArea
        }

        let result: ShadowResult
        do {
            result = try engine.evaluate(latitude: lat, longitude: lon, date: date, heightAboveGround: Self.observerHeight)
        } catch {
            throw ComputationError.noData
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let status: PointStatus
        var blockingId: String? = nil
        var intersectionDist: Double? = nil

        switch result.status {
        case .sun:
            status = .sun
        case .buildingShadow(let idx, let dist):
            status = .shadow
            blockingId = store.buildings[idx].id
            intersectionDist = dist
        case .night:
            status = .night
        case .insideBuilding:
            throw ComputationError.insideBuilding
        }

        let debug = DebugInfo(
            lat: lat,
            lon: lon,
            groundElevation: store.terrain.height(
                e: store.frame.enu(lat: lat, lon: lon, h: store.frame.h0).x,
                n: store.frame.enu(lat: lat, lon: lon, h: store.frame.h0).y
            ),
            solarAzimuth: result.solar?.azimuth ?? 0,
            solarElevation: result.solar?.elevation ?? 0,
            observerHeight: Self.observerHeight,
            checkedBuildingCount: store.buildings.count,
            blockingBuildingId: blockingId,
            intersectionDistance: intersectionDist,
            computationMs: elapsed,
            dataSource: "Amtliches Berliner LoD2"
        )

        return PointResult(status: status, sunAzimuth: result.solar?.azimuth ?? 0,
                           sunElevation: result.solar?.elevation ?? 0, debug: debug)
    }

    func analyzeDay(lat: Double, lon: Double, day: Date) throws -> DayAnalysis {
        guard let engine, let store, isReady else {
            throw ComputationError.engineNotReady
        }

        guard lat >= Self.minLat && lat <= Self.maxLat && lon >= Self.minLon && lon <= Self.maxLon else {
            throw ComputationError.outsideArea
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.berlinTZ

        let comps = cal.dateComponents([.year, .month, .day], from: day)
        guard let year = comps.year, let month = comps.month, let dayOfMonth = comps.day else {
            throw ComputationError.noData
        }

        let sunTimes: SunTimes
        do {
            sunTimes = try SolarPositionCalculator.sunTimes(
                year: year, month: month, day: dayOfMonth,
                timeZone: Self.berlinTZ,
                latitude: lat, longitude: lon,
                elevation: store.frame.h0
            )
        } catch {
            throw ComputationError.noData
        }

        let sunrise = sunTimes.sunrise
        let sunset = sunTimes.sunset

        guard let sunrise, let sunset else {
            // Polar day/night - single segment for entire day
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            // Check if sun is up at noon
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let noonResult: ShadowResult
            do {
                noonResult = try engine.evaluate(latitude: lat, longitude: lon, date: noon, heightAboveGround: Self.observerHeight)
            } catch {
                throw ComputationError.noData
            }
            let kind: PointStatus = noonResult.status == .night ? .night : .sun
            return DayAnalysis(sunrise: nil, sunset: nil,
                               segments: [TimelineSegment(start: dayStart, end: dayEnd, kind: kind)])
        }

        // Sample every 1 minute from sunrise to sunset
        var samples: [(Date, PointStatus)] = []
        var sampleTime = sunrise
        var sampleCount = 0

        while sampleTime <= sunset {
            try Task.checkCancellation()

            let result: ShadowResult
            do {
                result = try engine.evaluate(latitude: lat, longitude: lon, date: sampleTime, heightAboveGround: Self.observerHeight)
            } catch {
                sampleTime = sampleTime.addingTimeInterval(60)
                continue
            }

            let status: PointStatus
            switch result.status {
            case .sun: status = .sun
            case .buildingShadow: status = .shadow
            case .night: status = .night
            case .insideBuilding: throw ComputationError.insideBuilding
            }

            samples.append((sampleTime, status))
            sampleTime = sampleTime.addingTimeInterval(60)
            sampleCount += 1

            if sampleCount % 20 == 0 {
                try Task.checkCancellation()
            }
        }

        // Merge consecutive equal states into segments
        var segments: [TimelineSegment] = []

        // Night segment before sunrise
        let dayStart = cal.startOfDay(for: day)
        if sunrise > dayStart {
            segments.append(TimelineSegment(start: dayStart, end: sunrise, kind: .night))
        }

        // Build segments from samples
        if !samples.isEmpty {
            var segStart = samples[0].0
            var segKind = samples[0].1

            for i in 1..<samples.count {
                if samples[i].1 != segKind {
                    // Transition found - refine by bisection to 10s precision
                    let refinedTime = refineTransition(
                        engine: engine, lat: lat, lon: lon,
                        from: samples[i-1].0, to: samples[i].0,
                        fromStatus: segKind
                    )
                    segments.append(TimelineSegment(start: segStart, end: refinedTime, kind: segKind))
                    segStart = refinedTime
                    segKind = samples[i].1
                }
            }
            // Close last segment
            segments.append(TimelineSegment(start: segStart, end: sunset, kind: segKind))
        }

        // Night segment after sunset
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        if sunset < dayEnd {
            segments.append(TimelineSegment(start: sunset, end: dayEnd, kind: .night))
        }

        return DayAnalysis(sunrise: sunrise, sunset: sunset, segments: segments)
    }

    private func refineTransition(engine: ShadowEngine, lat: Double, lon: Double,
                                   from: Date, to: Date, fromStatus: PointStatus) -> Date {
        var lo = from
        var hi = to

        while hi.timeIntervalSince(lo) > 10 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            let result = try? engine.evaluate(latitude: lat, longitude: lon, date: mid, heightAboveGround: Self.observerHeight)

            let midStatus: PointStatus
            switch result?.status {
            case .sun: midStatus = .sun
            case .buildingShadow: midStatus = .shadow
            case .night: midStatus = .night
            case .insideBuilding: midStatus = .shadow
            case .none: midStatus = fromStatus
            }

            if midStatus == fromStatus {
                lo = mid
            } else {
                hi = mid
            }
        }

        return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
    }
}
