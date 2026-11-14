import Foundation

enum PointStatus: String, Equatable, Sendable {
    case sun
    case shadow
    case night
}

struct PointResult: Sendable {
    let status: PointStatus
    let sunAzimuth: Double
    let sunElevation: Double
    let debug: DebugInfo
}

struct TimelineSegment: Identifiable, Sendable {
    let id = UUID()
    let start: Date
    let end: Date
    let kind: PointStatus
}

struct DayAnalysis: Sendable {
    let sunrise: Date?
    let sunset: Date?
    let segments: [TimelineSegment]
}

enum ComputationError: Error, Equatable {
    case outsideArea
    case insideBuilding
    case noData
    case engineNotReady
}

struct DebugInfo: Sendable {
    let lat: Double
    let lon: Double
    let groundElevation: Double
    let solarAzimuth: Double
    let solarElevation: Double
    let observerHeight: Double
    let checkedBuildingCount: Int
    let blockingBuildingId: String?
    let intersectionDistance: Double?
    let computationMs: Double
    let dataSource: String
}
