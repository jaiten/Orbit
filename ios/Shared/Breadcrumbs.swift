import Foundation

/// Debug builds only: each step of a tick records itself, so after Orbit closes unexpectedly the next launch
/// can say how far it got. Used to find crashes in simulators that keep no crash log. Release builds do nothing.
enum Breadcrumbs {
    private static let key = "debugLastStep"
    #if DEBUG
    static func mark(_ step: String) {
        let defaults = UserDefaults.standard
        defaults.set(step + " · " + Date.now.formatted(date: .omitted, time: .standard), forKey: key)
        defaults.synchronize()
    }
    /// The step Orbit was in when it last closed without finishing, once; nil after a clean finish.
    static func takeUnfinished() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        guard let step = UserDefaults.standard.string(forKey: key), !step.hasPrefix("finished") else { return nil }
        return step
    }
    #else
    @inline(__always) static func mark(_ step: String) {}
    static func takeUnfinished() -> String? { nil }
    #endif
}
