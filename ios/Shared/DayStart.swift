import Foundation

/// When a new planner day begins (Settings → Day starts at), synced as one preferences record.
/// Minutes after midnight: -60 is 11 PM the evening before, 240 is 4 AM, in 30-minute steps; 2 AM by
/// default. Until then, "today", check-ins, finished tasks and new habits count for the day before;
/// scheduled dates and times never move. Mirrors windows/ui/planner.js; cases in
/// shared/test-cases/day-start.json. Stored in the shared app group so widgets agree.
enum DayStart {
    static let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let defaultMinutes = 120
    static let choices = Array(stride(from: -60, through: 240, by: 30))
    private static let minutesKey = "dayStartMinutes", updatedKey = "dayStartUpdatedAt"
    private static var defaults: UserDefaults { DayTheme.sharedDefaults ?? .standard }

    static func sanitized(_ value: Int?) -> Int { value.map { choices.contains($0) } == true ? value! : defaultMinutes }
    /// The current setting (the default until someone chooses one).
    static var minutes: Int { sanitized(defaults.object(forKey: minutesKey) as? Int) }
    /// Milliseconds since 1970 when the setting last changed; 0 if it never has (nothing to sync yet).
    static var updatedAt: Double { defaults.double(forKey: updatedKey) }

    /// Chosen in Settings on this device.
    static func choose(_ value: Int) {
        defaults.set(sanitized(value), forKey: minutesKey)
        defaults.set((Date.now.timeIntervalSince1970 * 1000).rounded(), forKey: updatedKey)
    }
    /// Received from another device.
    static func receive(minutes value: Int?, updatedAt stamp: Double) {
        defaults.set(sanitized(value), forKey: minutesKey)
        defaults.set(stamp, forKey: updatedKey)
    }

    /// `date` moved back by the day start, so its calendar day is the planner day.
    static func shifted(_ date: Date, minutes: Int? = nil) -> Date {
        date.addingTimeInterval(-Double(sanitized(minutes ?? self.minutes)) * 60)
    }

    /// "2:00 AM", "Midnight", "11:30 PM (the evening before)".
    static func label(_ value: Int) -> String {
        let minutes = sanitized(value)
        if minutes == 0 { return "Midnight" }
        let clock = (minutes + 1440) % 1440, hour = clock / 60
        let text = "\(hour % 12 == 0 ? 12 : hour % 12):" + String(format: "%02d", clock % 60) + (hour < 12 ? " AM" : " PM")
        return minutes < 0 ? text + " (the evening before)" : text
    }
}
