import Foundation
import Observation
import CoreLocation
import os.log

private let logger = Logger(subsystem: "de.sonnenschein.app", category: "AppModel")

enum PointState: Equatable {
    case idle
    case loading
    case result(PointResult)
    case error(ComputationError)

    static func == (lhs: PointState, rhs: PointState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading, .loading): return true
        case (.result(let a), .result(let b)): return a.status == b.status
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

enum DayState {
    case idle
    case loading
    case loaded(DayAnalysis)
    case error
}

@Observable
@MainActor
final class AppModel {
    var selectedCoordinate: CLLocationCoordinate2D?
    var selectedDay: Date = AppModel.todayBerlin()
    var selectedTime: Date = Date()
    var pointState: PointState = .idle
    var dayState: DayState = .idle
    var showsLoadingIndicator: Bool = false
    var engineReady: Bool = false

    private var pointTask: Task<Void, Never>?
    private var dayTask: Task<Void, Never>?
    private var loadingDelayTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    let computationService = SolarComputationService()

    private static let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    static func todayBerlin() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = berlinTZ
        return cal.startOfDay(for: Date())
    }

    func initializeEngine() {
        Task.detached { [weak self] in
            guard let self else { return }
            let service = await self.computationService
            await service.loadData()
            await MainActor.run {
                self.engineReady = true
                logger.info("Engine bereit")
                // If a coordinate was selected while loading, evaluate now
                if self.selectedCoordinate != nil {
                    self.evaluateCurrentPoint()
                    self.analyzeCurrentDay()
                }
            }
        }
    }

    func selectPoint(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        evaluateCurrentPoint()
        analyzeCurrentDay()
    }

    func updateSelectedTime(_ time: Date) {
        selectedTime = time
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            await self?.evaluateCurrentPoint()
        }
    }

    func updateSelectedDay(_ day: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.berlinTZ
        selectedDay = cal.startOfDay(for: day)
        evaluateCurrentPoint()
        analyzeCurrentDay()
    }

    func evaluateCurrentPoint() {
        pointTask?.cancel()
        guard let coord = selectedCoordinate else { return }
        guard engineReady else {
            pointState = .loading
            return
        }

        let time = selectedTime
        let previousState = pointState

        // Only show loading indicator after 300ms
        loadingDelayTask?.cancel()
        showsLoadingIndicator = false
        loadingDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.showsLoadingIndicator = true
        }

        pointTask = Task { [weak self] in
            guard let self else { return }
            let service = self.computationService
            do {
                let result = try await service.evaluate(lat: coord.latitude, lon: coord.longitude, at: time)
                guard !Task.isCancelled else { return }
                self.pointState = .result(result)
            } catch let error as ComputationError {
                guard !Task.isCancelled else { return }
                self.pointState = .error(error)
            } catch {
                guard !Task.isCancelled else { return }
                if !Task.isCancelled {
                    self.pointState = .error(.engineNotReady)
                }
            }
            self.loadingDelayTask?.cancel()
            self.showsLoadingIndicator = false
        }
    }

    func analyzeCurrentDay() {
        dayTask?.cancel()
        guard let coord = selectedCoordinate else { return }
        guard engineReady else {
            dayState = .loading
            return
        }

        let day = selectedDay
        dayState = .loading

        dayTask = Task { [weak self] in
            guard let self else { return }
            let service = self.computationService
            do {
                let analysis = try await service.analyzeDay(lat: coord.latitude, lon: coord.longitude, day: day)
                guard !Task.isCancelled else { return }
                self.dayState = .loaded(analysis)
            } catch {
                guard !Task.isCancelled else { return }
                self.dayState = .error
            }
        }
    }

    // MARK: - Derived state

    var nextChangeText: String? {
        guard case .loaded(let analysis) = dayState,
              case .result(let point) = pointState else { return nil }
        return Self.deriveNextChangeText(analysis: analysis, status: point.status, at: selectedTime)
    }

    static func deriveNextChangeText(analysis: DayAnalysis, status: PointStatus, at time: Date) -> String? {
        let formatter = Formatters.timeFormatter

        // Find the segment containing the selected time
        guard let currentSegment = analysis.segments.first(where: { $0.start <= time && time < $0.end }) else {
            return nil
        }

        switch currentSegment.kind {
        case .sun:
            return "Sonne bis \(formatter.string(from: currentSegment.end))"
        case .shadow:
            // Find next sun segment
            if let nextSun = analysis.segments.first(where: { $0.kind == .sun && $0.start >= currentSegment.end }) {
                return "Sonne ab \(formatter.string(from: nextSun.start))"
            }
            return "Heute keine Sonne mehr"
        case .night:
            if let sunrise = analysis.sunrise, time < sunrise {
                return "Sonnenaufgang um \(formatter.string(from: sunrise))"
            }
            if let sunset = analysis.sunset {
                return "Sonnenuntergang war um \(formatter.string(from: sunset))"
            }
            return nil
        }
    }

    var totalSunDuration: TimeInterval {
        guard case .loaded(let analysis) = dayState else { return 0 }
        return analysis.segments.filter { $0.kind == .sun }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    var sunSegments: [TimelineSegment] {
        guard case .loaded(let analysis) = dayState else { return [] }
        return analysis.segments.filter { $0.kind == .sun }
    }

    var shadowSegments: [TimelineSegment] {
        guard case .loaded(let analysis) = dayState else { return [] }
        return analysis.segments.filter { $0.kind == .shadow }
    }
}
