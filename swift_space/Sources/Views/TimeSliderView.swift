import SwiftUI

struct TimeSliderView: View {
    @Environment(AppModel.self) private var appModel
    let analysis: DayAnalysis

    @State private var lastBoundaryStatus: PointStatus?

    private var sunriseTime: Date { analysis.sunrise ?? appModel.selectedDay }
    private var sunsetTime: Date {
        analysis.sunset ?? appModel.selectedDay.addingTimeInterval(86400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Uhrzeit")
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Text(Formatters.timeFormatter.string(from: appModel.selectedTime))
                    .font(Theme.Fonts.monoLarge)
                    .foregroundStyle(Theme.Colors.primaryText)
            }

            // Slider
            if let sunrise = analysis.sunrise, let sunset = analysis.sunset {
                let range = sunrise.timeIntervalSinceReferenceDate...sunset.timeIntervalSinceReferenceDate
                @Bindable var model = appModel
                let sliderBinding = Binding<Double>(
                    get: {
                        let t = appModel.selectedTime.timeIntervalSinceReferenceDate
                        return min(max(t, range.lowerBound), range.upperBound)
                    },
                    set: { newValue in
                        let newTime = Date(timeIntervalSinceReferenceDate: newValue)
                        appModel.updateSelectedTime(newTime)
                        checkBoundary(at: newTime)
                    }
                )

                Slider(value: sliderBinding, in: range, step: 60)
                    .tint(Theme.Colors.sunYellow)
                    .accessibilityValue(sliderAccessibilityValue)

                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "sunrise")
                            .font(.caption2)
                        Text(Formatters.timeFormatter.string(from: sunrise))
                            .font(Theme.Fonts.monoCaption)
                    }
                    .foregroundStyle(Theme.Colors.secondaryText)

                    Spacer()

                    nowButton

                    Spacer()

                    HStack(spacing: 2) {
                        Image(systemName: "sunset")
                            .font(.caption2)
                        Text(Formatters.timeFormatter.string(from: sunset))
                            .font(Theme.Fonts.monoCaption)
                    }
                    .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
    }

    private var nowButton: some View {
        Button(action: {
            appModel.selectedTime = Date()
            if !Formatters.isToday(appModel.selectedDay) {
                appModel.updateSelectedDay(Date())
            } else {
                appModel.evaluateCurrentPoint()
            }
        }) {
            Text("Jetzt")
                .font(Theme.Fonts.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.sunYellow)
                .foregroundStyle(Color(hex: 0x1C1E21))
                .clipShape(Capsule())
        }
    }

    private func checkBoundary(at time: Date) {
        // Find which segment the time is in
        if let segment = analysis.segments.first(where: { $0.start <= time && time < $0.end }) {
            if let last = lastBoundaryStatus, last != segment.kind {
                // Crossed a boundary - trigger haptic handled by sensoryFeedback
            }
            lastBoundaryStatus = segment.kind
        }
    }

    private var sliderAccessibilityValue: String {
        let time = Formatters.timeFormatter.string(from: appModel.selectedTime)
        if case .result(let result) = appModel.pointState {
            return "\(time), \(result.status.title)"
        }
        return time
    }
}
