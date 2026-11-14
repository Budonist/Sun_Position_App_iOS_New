import SwiftUI
import MapKit
import os.log

private let logger = Logger(subsystem: "de.sonnenschein.app", category: "Map")

struct MapScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var locationProvider = LocationProvider()
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 52.4935, longitude: 13.4040),
                  distance: 2500)
    )
    @State private var showSheet = true
    @State private var selectedDetent: PresentationDetent = .height(140)
    @State private var hasSelectedFirstPoint = false

    // PLZ 10961 approximate boundary
    private let coverageBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 52.4875, longitude: 13.3830),
        CLLocationCoordinate2D(latitude: 52.4875, longitude: 13.4250),
        CLLocationCoordinate2D(latitude: 52.5015, longitude: 13.4250),
        CLLocationCoordinate2D(latitude: 52.5015, longitude: 13.3830),
        CLLocationCoordinate2D(latitude: 52.4875, longitude: 13.3830),
    ]

    var body: some View {
        ZStack {
            mapView
            floatingControls
        }
        .sheet(isPresented: $showSheet) {
            SolarResultSheet(
                locationProvider: locationProvider,
                onRecenter: recenterMap
            )
            .presentationDetents([.height(140), .medium, .large], selection: $selectedDetent)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
            .presentationCornerRadius(Theme.Radius.sheet)
        }
        .onAppear {
            appModel.initializeEngine()
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Coverage outline
                MapPolyline(coordinates: coverageBoundary)
                    .stroke(Theme.Colors.sunYellow.opacity(0.6), lineWidth: 2)

                // User annotation
                if locationProvider.authorizationStatus == .authorizedWhenInUse ||
                   locationProvider.authorizationStatus == .authorizedAlways {
                    UserAnnotation()
                }

                // Selected point marker
                if let coord = appModel.selectedCoordinate {
                    Annotation("", coordinate: coord) {
                        MarkerView(pointState: appModel.pointState)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    logger.info("Punkt gew\u{00E4}hlt: \(coordinate.latitude), \(coordinate.longitude)")
                    appModel.selectPoint(coordinate)
                    if !hasSelectedFirstPoint {
                        hasSelectedFirstPoint = true
                        selectedDetent = .medium
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var floatingControls: some View {
        VStack {
            // Date/Time header capsule
            DateTimeHeader()
                .environment(appModel)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)

            Spacer()

            // Bottom-right floating buttons
            HStack {
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    FloatingButton(symbol: "location", label: "Mein Standort") {
                        locationProvider.requestLocation()
                        if let loc = locationProvider.userLocation {
                            cameraPosition = .camera(
                                MapCamera(centerCoordinate: loc, distance: 1500)
                            )
                        }
                    }
                    FloatingButton(symbol: "scope", label: "Auf 10961 zentrieren") {
                        recenterMap()
                    }
                }
                .padding(.trailing, Theme.Spacing.md)
                .padding(.bottom, 160)
            }
        }
    }

    private func recenterMap() {
        cameraPosition = .camera(
            MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 52.4935, longitude: 13.4040),
                      distance: 2500)
        )
    }
}

// MARK: - Marker View

struct MarkerView: View {
    let pointState: PointState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(markerColor)
                .frame(width: 28, height: 28)
                .overlay {
                    Circle().stroke(.white, lineWidth: 2)
                }
                .overlay {
                    Image(systemName: markerSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(symbolColor)
                }
        }
        .scaleEffect(appeared ? 1.0 : 0.6)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: appeared)
        .onAppear { appeared = true }
        .accessibilityLabel(accessibilityLabel)
    }

    private var markerColor: Color {
        switch pointState {
        case .result(let r): return r.status.color
        case .error: return Color.gray
        case .loading: return Color.gray.opacity(0.6)
        case .idle: return Color.gray.opacity(0.6)
        }
    }

    private var markerSymbol: String {
        switch pointState {
        case .result(let r): return r.status.symbolName
        case .error: return "exclamationmark"
        case .loading, .idle: return "ellipsis"
        }
    }

    private var symbolColor: Color {
        switch pointState {
        case .result(let r): return r.status.symbolOnColor
        default: return .white
        }
    }

    private var accessibilityLabel: String {
        switch pointState {
        case .result(let r): return "Gew\u{00E4}hlter Punkt, \(r.status.title)"
        case .error: return "Gew\u{00E4}hlter Punkt, Fehler"
        case .loading: return "Gew\u{00E4}hlter Punkt, wird berechnet"
        case .idle: return "Gew\u{00E4}hlter Punkt"
        }
    }
}

// MARK: - Floating Button

struct FloatingButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Theme.Colors.surface)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                }
        }
        .foregroundStyle(Theme.Colors.primaryText)
        .accessibilityLabel(label)
    }
}

// MARK: - DateTimeHeader

struct DateTimeHeader: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(Formatters.weekdayDateFormatter.string(from: appModel.selectedDay))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.primaryText)

            Spacer()

            Text(Formatters.timeFormatter.string(from: appModel.selectedTime))
                .font(Theme.Fonts.monoTime)
                .foregroundStyle(Theme.Colors.primaryText)

            if !isCurrentTime {
                Button("Jetzt") {
                    appModel.selectedTime = Date()
                    appModel.selectedDay = AppModel.todayBerlin()
                    appModel.evaluateCurrentPoint()
                    appModel.analyzeCurrentDay()
                }
                .font(Theme.Fonts.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.sunYellow)
                .foregroundStyle(Color(hex: 0x1C1E21))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background {
            Capsule()
                .fill(Theme.Colors.surface)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    private var isCurrentTime: Bool {
        let diff = abs(appModel.selectedTime.timeIntervalSinceNow)
        return diff < 60 && Formatters.isToday(appModel.selectedDay)
    }
}
