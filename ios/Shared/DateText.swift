import Foundation

/// "Monday, November 2nd" for Today's heading. Mirrors longDate in windows/ui/core.js.
enum DateText {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
    static func long(_ date: Date, calendar: Calendar = .current) -> String {
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date) + ordinal(calendar.component(.day, from: date))
    }
    static func ordinal(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
