#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

struct DebugPanelView: View {
    let debug: DebugInfo

    var body: some View {
        List {
            Section("Position") {
                debugRow("Breite", String(format: "%.6f", debug.lat))
                debugRow("L\u{00E4}nge", String(format: "%.6f", debug.lon))
                debugRow("Gel\u{00E4}ndeh\u{00F6}he", String(format: "%.1f m", debug.groundElevation))
            }

            Section("Sonnenstand") {
                debugRow("Sonnenazimut", String(format: "%.2f\u{00B0}", debug.solarAzimuth))
                debugRow("Sonnenh\u{00F6}he", String(format: "%.2f\u{00B0}", debug.solarElevation))
            }

            Section("Beobachter") {
                debugRow("Beobachterh\u{00F6}he", String(format: "%.1f m", debug.observerHeight))
            }

            Section("Gebäude") {
                debugRow("Gepr\u{00FC}fte Geb\u{00E4}ude", "\(debug.checkedBuildingCount)")
                debugRow("Blockierendes Geb\u{00E4}ude", debug.blockingBuildingId ?? "\u{2013}")
                debugRow("Schnittdistanz", debug.intersectionDistance.map { String(format: "%.1f m", $0) } ?? "\u{2013}")
            }

            Section("Leistung") {
                debugRow("Rechenzeit", String(format: "%.1f ms", debug.computationMs))
                debugRow("Datenquelle", debug.dataSource)
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Kopieren") {
                    UIPasteboard.general.string = debugText
                }
            }
        }
        .font(Theme.Fonts.body.monospacedDigit())
        .textSelection(.enabled)
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.Colors.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Colors.primaryText)
                .font(Theme.Fonts.monoTime)
        }
    }

    private var debugText: String {
        """
        Breite: \(String(format: "%.6f", debug.lat))
        L\u{00E4}nge: \(String(format: "%.6f", debug.lon))
        Gel\u{00E4}ndeh\u{00F6}he: \(String(format: "%.1f m", debug.groundElevation))
        Sonnenazimut: \(String(format: "%.2f\u{00B0}", debug.solarAzimuth))
        Sonnenh\u{00F6}he: \(String(format: "%.2f\u{00B0}", debug.solarElevation))
        Beobachterh\u{00F6}he: \(String(format: "%.1f m", debug.observerHeight))
        Gepr\u{00FC}fte Geb\u{00E4}ude: \(debug.checkedBuildingCount)
        Blockierendes Geb\u{00E4}ude: \(debug.blockingBuildingId ?? "\u{2013}")
        Schnittdistanz: \(debug.intersectionDistance.map { String(format: "%.1f m", $0) } ?? "\u{2013}")
        Rechenzeit: \(String(format: "%.1f ms", debug.computationMs))
        Datenquelle: \(debug.dataSource)
        """
    }
}
#endif
