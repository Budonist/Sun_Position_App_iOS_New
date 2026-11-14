import SwiftUI

struct StatusBadge: View {
    let status: PointStatus
    let subtitle: String?
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: compact ? Theme.Spacing.sm : Theme.Spacing.md) {
            symbolTile
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(status.title)
                    .font(compact ? Theme.Fonts.headline : Theme.Fonts.display)
                    .foregroundStyle(Theme.Colors.primaryText)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(compact ? Theme.Fonts.caption : Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbolTile: some View {
        let size: CGFloat = compact ? 32 : 52
        return RoundedRectangle(cornerRadius: Theme.Radius.symbolTile)
            .fill(status.color)
            .overlay {
                if status == .night {
                    RoundedRectangle(cornerRadius: Theme.Radius.symbolTile)
                        .stroke(Theme.Colors.nightBorder, lineWidth: 1)
                }
            }
            .overlay {
                Image(systemName: status.symbolName)
                    .font(.system(size: compact ? 16 : 24))
                    .foregroundStyle(status.symbolOnColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
    }

    private var accessibilityLabel: String {
        var label = status.title
        if let subtitle { label += ". \(subtitle)" }
        return label
    }
}
