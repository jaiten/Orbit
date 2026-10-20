import AppIntents

/// Phrases for Shortcuts and Siri: add with quick add rules, or tick off one of today's items.
struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToOrbitIntent(), phrases: ["Add to \(.applicationName)", "Add a task to \(.applicationName)"],
                    shortTitle: "Add to Orbit", systemImageName: "plus.circle")
        AppShortcut(intent: CompleteItemIntent(), phrases: ["Complete an item in \(.applicationName)", "Tick off something in \(.applicationName)"],
                    shortTitle: "Complete Item", systemImageName: "checkmark.circle")
    }
}
