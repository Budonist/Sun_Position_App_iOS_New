import SwiftUI

struct SolarResultSheet: View {
    @Environment(AppModel.self) private var appModel
    let locationProvider: LocationProvider
    let onRecenter: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Main content based on state
                    mainContent
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !appModel.engineReady {
            engineLoadingView
        } else if appModel.selectedCoordinate == nil {
            hintView
        } else {
            switch appModel.pointState {
            case .idle:
                hintView
            case .loading:
                loadingContentView
            case .result(let result):
                resultContent(result)
            case .error(let error):
                errorContent(error)
            }
        }

        // Location denied banner
        if locationProvider.locationDenied {
            locationDeniedBanner
        }
    }

    // MARK: - Hint / Empty

    private var hintView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "hand.tap")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.secondaryText)
            Text("Tippe auf die Karte")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Colors.primaryText)
            Text("W\u{00E4}hle einen Ort in 10961 und sieh sofort, ob dort die Sonne scheint.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var engineLoadingView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Geb\u{00E4}udedaten werden geladen \u{2026}")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var loadingContentView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if appModel.showsLoadingIndicator {
                ProgressView()
            }
            Text("Berechnung l\u{00E4}uft\u{2026}")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Result

    @ViewBuilder
    private func resultContent(_ result: PointResult) -> some View {
        StatusBadge(status: result.status, subtitle: appModel.nextChangeText)

        if case .loaded(let analysis) = appModel.dayState {
            // Time slider
            TimeSliderView(analysis: analysis)
                .environment(appModel)

            Divider().background(Theme.Colors.separator)

            // Day timeline
            DayTimelineSection(analysis: analysis)
                .environment(appModel)

            Divider().background(Theme.Colors.separator)

            // Sun windows list
            SunWindowsList(analysis: analysis)

            Divider().background(Theme.Colors.separator)
        } else if case .loading = appModel.dayState {
            DayTimelinePlaceholder()
        }

        // Date selector
        DateSelectorView()
            .environment(appModel)

        Divider().background(Theme.Colors.separator)

        // Attribution
        attributionSection

        #if DEBUG
        // Debug link
        NavigationLink {
            DebugPanelView(debug: result.debug)
        } label: {
            HStack {
                Text("Debug-Informationen")
                    .font(Theme.Fonts.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .foregroundStyle(Theme.Colors.primaryText)
        #endif
    }

    // MARK: - Error

    @ViewBuilder
    private func errorContent(_ error: ComputationError) -> some View {
        switch error {
        case .insideBuilding:
            InfoCard(
                symbol: "building.fill",
                title: "Dieser Punkt befindet sich innerhalb eines Geb\u{00E4}udes."
            )
        case .outsideArea:
            InfoCard(
                symbol: "mappin.slash",
                title: "Au\u{00DF}erhalb des unterst\u{00FC}tzten Gebiets.",
                subtitle: "Unterst\u{00FC}tzt wird derzeit nur das Gebiet der PLZ 10961.",
                buttonTitle: "Auf 10961 zentrieren",
                buttonAction: onRecenter
            )
        case .noData:
            InfoCard(
                symbol: "questionmark.square.dashed",
                title: "F\u{00FC}r diesen Punkt liegen keine Geb\u{00E4}udedaten vor."
            )
        case .engineNotReady:
            InfoCard(
                symbol: "exclamationmark.triangle",
                title: "Berechnung fehlgeschlagen.",
                buttonTitle: "Erneut versuchen"
            ) {
                appModel.evaluateCurrentPoint()
                appModel.analyzeCurrentDay()
            }
        }

        // Date selector still visible on error
        DateSelectorView()
            .environment(appModel)
    }

    // MARK: - Attribution

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "info.circle")
                    .font(Theme.Fonts.caption)
                Text("Datenquelle: Amtliches Berliner LoD2 \u{00B7} Geoportal Berlin")
                    .font(Theme.Fonts.caption)
            }
            .foregroundStyle(Theme.Colors.secondaryText)

            Text("Beobachterh\u{00F6}he 1,2\u{202F}m \u{00FC}ber Boden")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Location denied

    private var locationDeniedBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "location.slash")
                .foregroundStyle(Theme.Colors.warningTint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Standortzugriff ist deaktiviert.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.primaryText)
                Text("Du kannst ihn in den Einstellungen erlauben.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
            Button("Einstellungen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(Theme.Fonts.caption.weight(.semibold))
        }
        .padding(Theme.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.surface)
        }
    }
}
