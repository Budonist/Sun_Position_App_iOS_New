import SwiftUI

struct SunWindowsList: View {
    let analysis: DayAnalysis

    private var daylightSegments: [TimelineSegment] {
        analysis.segments.filter { $0.kind != .night }
    }

    private var hasSunSegments: Bool {
        analysis.segments.contains { $0.kind == .sun }
    }

    private var totalSunDuration: TimeInterval {
        analysis.segments.filter { $0.kind == .sun }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !hasSunSegments {
                Text("An diesem Tag erreicht kein direktes Sonnenlicht diesen Punkt.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.vertical, Theme.Spacing.xs)
            } else {
                ForEach(daylightSegments) { segment in
                    segmentRow(segment)
                }

                HStack {
                    Image(systemName: "sum")
                        .foregroundStyle(Theme.Colors.sunYellow)
                    Text("Insgesamt \(Formatters.durationString(from: totalSunDuration)) Sonne")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.primaryText)
                }
                .padding(.top, Theme.Spacing.xxs)
            }
        }
    }

    private func segmentRow(_ segment: TimelineSegment) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: segment.kind == .sun ? "sun.max" : "building.2")
                .font(.body)
                .foregroundStyle(segment.kind == .sun ? Theme.Colors.sunYellow : Theme.Colors.shadowSlate)
                .frame(width: 24)

            Text("\(Formatters.timeFormatter.string(from: segment.start)) \u{2013} \(Formatters.timeFormatter.string(from: segment.end))")
                .font(Theme.Fonts.monoTime)
                .foregroundStyle(Theme.Colors.primaryText)

            Spacer()

            let duration = segment.end.timeIntervalSince(segment.start)
            Text(Formatters.durationString(from: duration))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: 44)
    }
}
