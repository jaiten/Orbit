import Foundation

/// Device preferences shared with extensions; absent values retain the shipped defaults.
enum PlannerPreferences {
    static var includesTasks: Bool {
        let defaults = DayTheme.sharedDefaults ?? .standard
        return defaults.object(forKey: "progressIncludesTasks") as? Bool ?? true
    }
}
