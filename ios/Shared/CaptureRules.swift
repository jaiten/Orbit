import Foundation

/// Quick add rules (Settings → Quick add rules), synced as one preferences record like Day starts at.
/// - progressWords: words that always turn on start & finish for a new task with one of them in its title.
/// The same screen holds the Someday visibility rules (SomedayRules), synced as their own record.
/// Mirrors windows/ui/capture-rules.js; cases in shared/test-cases/progress-learning.json.
enum CaptureRules {
    static let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let wordsKey = "captureRuleProgressWords", updatedKey = "captureRulesUpdatedAt"
    private static var defaults: UserDefaults { DayTheme.sharedDefaults ?? .standard }

    static var progressWords: [String] { defaults.stringArray(forKey: wordsKey) ?? [] }
    /// Milliseconds since 1970 when the rules last changed; 0 if they never have (nothing to sync yet).
    static var updatedAt: Double { defaults.double(forKey: updatedKey) }

    /// Changed in Settings on this device.
    static func save(progressWords: [String]) {
        defaults.set(progressWords, forKey: wordsKey)
        defaults.set((Date.now.timeIntervalSince1970 * 1000).rounded(), forKey: updatedKey)
    }
    /// The synced record's fields (besides id).
    static var payload: [String: Any] { ["progressWords": progressWords, "updatedAt": updatedAt] }
    /// Received from another device.
    static func receive(_ payload: [String: Any]) {
        defaults.set((payload["progressWords"] as? [String] ?? []).filter { !$0.isEmpty }, forKey: wordsKey)
        defaults.set(payload["updatedAt"] as? Double ?? 0, forKey: updatedKey)
    }
}
