import Foundation

/// Suggestions are conservative and never change a task without the user's choice.
enum TaskProgress {
    static func suggests(_ title: String) -> Bool {
        let words = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let text = " " + words.joined(separator: " ") + " "
        if ["buy", "shop", "fold", "put away", "unload", "empty", "clean", "repair"].contains(where: { text.hasPrefix(" " + $0 + " ") }) { return false }
        return ["laundry", "dishwasher", "washing machine", "wash clothes", "dry clothes",
                "bake", "baking", "roast", "roasting", "slow cook", "meal prep",
                "defrost", "marinate", "marinating", "charge car", "charge battery"].contains { text.contains(" " + $0 + " ") }
    }
}
