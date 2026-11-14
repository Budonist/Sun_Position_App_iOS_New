import SwiftUI

struct DayTimelineSection: View {
    @Environment(AppModel.self) private var appModel
    let analysis: DayAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Tagesverlauf")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)

            DayTimelineBar(analysis: analysis, selectedTime: appModel.selectedTime)
                .frame(height: 20)
                .onTapGesture { location in
                    // Handle tap on timeline - not using location in the limited way here
                }

            // Time labels
            timeLabels

            // Legend
            legendRow
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var timeLabels: some View {
        HStack {
            if let sunrise = analysis.sunrise {
                Text(Formatters.timeFormatter.string(from: sunrise))
                    .font(Theme.Fonts.monoCaption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
            Text("12:00")
                .font(Theme.Fonts.monoCaption)
                .foregroundStyle(Theme.Colors.secondaryText)
            Spacer()
            if let sunset = analysis.sunset {
                Text(Formatters.timeFormatter.string(from: sunset))
                    .font(Theme.Fonts.monoCaption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendItem(color: Theme.Colors.sunYellow, label: "Sonne")
            legendItem(color: Theme.Colors.shadowSlate, label: "Schatten")
            legendItem(color: Theme.Colors.night, label: "Nacht")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = ["Tagesverlauf:"]
        for seg in analysis.segments where seg.kind != .night {
            let start = Formatters.timeFormatter.string(from: seg.start)
            let end = Formatters.timeFormatter.string(from: seg.end)
            parts.append("\(seg.kind == .sun ? "Sonne" : "Schatten") \(start) bis \(end)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Timeline Bar

struct DayTimelineBar: View {
    let analysis: DayAnalysis
    let selectedTime: Date

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Colors.night)

                // Segments
                if let sunrise = analysis.sunrise, let sunset = analysis.sunset {
                    let dayStart = Formatters.berlinCalendar.startOfDay(for: analysis.sunrise ?? Date())
                    let dayEnd = dayStart.addingTimeInterval(86400)
                    let totalDuration = dayEnd.timeIntervalSince(dayStart)

                    ForEach(analysis.segments) { segment in
                        let startFrac = segment.start.timeIntervalSince(dayStart) / totalDuration
                        let endFrac = segment.end.timeIntervalSince(dayStart) / totalDuration
                        let segWidth = (endFrac - startFrac) * width
                        let segX = startFrac * width

                        Rectangle()
                            .fill(segmentColor(segment.kind))
                            .frame(width: max(0, segWidth))
                            .offset(x: segX)
                    }

                    // Needle for selected time
                    let timeFrac = selectedTime.timeIntervalSince(dayStart) / totalDuration
                    let clampedFrac = min(max(timeFrac, 0), 1)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white)
                        .frame(width: 2, height: 24)
                        .shadow(color: .black.opacity(0.3), radius: 1)
                        .offset(x: clampedFrac * width - 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func segmentColor(_ kind: PointStatus) -> Color {
        switch kind {
        case .sun: return Theme.Colors.sunYellow
        case .shadow: return Theme.Colors.shadowSlate
        case .night: return Theme.Colors.night
        }
    }
}

struct DayTimelinePlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Tagesverlauf")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Colors.loadingNeutral)
                .frame(height: 20)
        }
    }
}
