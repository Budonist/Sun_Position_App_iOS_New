import Foundation

enum Formatters {
    static let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = berlinTZ
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E., d. MMMM"
        f.timeZone = berlinTZ
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d. MMMM"
        f.timeZone = berlinTZ
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    static let weekdayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E., d. MMMM"
        f.timeZone = berlinTZ
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    static func durationString(from interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours) Std. \(minutes) Min."
        } else if hours > 0 {
            return "\(hours) Std."
        } else {
            return "\(minutes) Min."
        }
    }

    static var berlinCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = berlinTZ
        cal.locale = Locale(identifier: "de_DE")
        return cal
    }

    static func isToday(_ date: Date) -> Bool {
        berlinCalendar.isDateInToday(date)
    }

    static func isTomorrow(_ date: Date) -> Bool {
        berlinCalendar.isDateInTomorrow(date)
    }
}
