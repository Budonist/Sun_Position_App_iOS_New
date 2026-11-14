import SwiftUI

struct DateSelectorView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showDatePicker = false
    @State private var customDate: Date?

    private enum DateOption: Int, CaseIterable {
        case today = 0
        case tomorrow = 1
        case custom = 2
    }

    private var selectedOption: DateOption {
        if Formatters.isToday(appModel.selectedDay) { return .today }
        if Formatters.isTomorrow(appModel.selectedDay) { return .tomorrow }
        return .custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Datum")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)

            Picker("Datum", selection: Binding<Int>(
                get: { selectedOption.rawValue },
                set: { newValue in
                    switch DateOption(rawValue: newValue) {
                    case .today:
                        appModel.updateSelectedDay(Date())
                        customDate = nil
                    case .tomorrow:
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                        appModel.updateSelectedDay(tomorrow)
                        customDate = nil
                    case .custom:
                        showDatePicker = true
                    case .none:
                        break
                    }
                }
            )) {
                Text("Heute").tag(0)
                Text("Morgen").tag(1)
                Text(customDateLabel).tag(2)
            }
            .pickerStyle(.segmented)
        }
        .sheet(isPresented: $showDatePicker) {
            CustomDateSheet(selectedDate: appModel.selectedDay) { date in
                customDate = date
                appModel.updateSelectedDay(date)
            }
        }
    }

    private var customDateLabel: String {
        if let custom = customDate {
            return Formatters.shortDateFormatter.string(from: custom)
        }
        return "Datum w\u{00E4}hlen"
    }
}

// MARK: - Custom Date Sheet

struct CustomDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date
    let onSelect: (Date) -> Void

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        self._pickerDate = State(initialValue: selectedDate)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Datum w\u{00E4}hlen",
                selection: $pickerDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .padding()
            .navigationTitle("Datum w\u{00E4}hlen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onSelect(pickerDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
