// Generated from shared/icons.json. Run npm run generate.
import Foundation

enum ItemIcons {
    struct Icon: Identifiable { let id: String; let name: String; let words: [String] }
    static let all: [Icon] = [
        Icon(id: "dumbbell", name: "Gym", words: ["gym", "workout", "work out", "weights", "strength", "lifting"]),
        Icon(id: "figure.walk", name: "Walking", words: ["walk", "walking", "steps", "hike", "hiking"]),
        Icon(id: "figure.run", name: "Running", words: ["run", "running", "jog", "jogging"]),
        Icon(id: "bicycle", name: "Cycling", words: ["bike", "cycling", "bicycle", "cycle"]),
        Icon(id: "figure.pool.swim", name: "Swimming", words: ["swim", "swimming", "pool"]),
        Icon(id: "figure.mind.and.body", name: "Mindfulness", words: ["meditate", "meditation", "mindfulness", "breathe", "breathing"]),
        Icon(id: "figure.yoga", name: "Yoga", words: ["yoga", "stretch", "stretching", "pilates"]),
        Icon(id: "drop", name: "Water", words: ["water", "hydrate", "hydration"]),
        Icon(id: "book", name: "Reading", words: ["read", "reading", "book", "books"]),
        Icon(id: "pencil", name: "Writing", words: ["write", "writing", "journal", "journaling", "diary"]),
        Icon(id: "moon", name: "Sleep", words: ["sleep", "bedtime", "bed", "nap"]),
        Icon(id: "sun.max", name: "Morning", words: ["morning", "sunlight", "sunrise"]),
        Icon(id: "fork.knife", name: "Meals", words: ["eat", "meal", "meals", "lunch", "dinner", "breakfast"]),
        Icon(id: "carrot", name: "Cooking", words: ["cook", "cooking", "vegetables", "meal prep"]),
        Icon(id: "cup.and.saucer", name: "Coffee", words: ["coffee", "tea"]),
        Icon(id: "pills", name: "Medicine", words: ["medicine", "medication", "vitamins", "supplements", "pills"]),
        Icon(id: "cross.case", name: "Health", words: ["doctor", "dentist", "therapy", "appointment", "checkup"]),
        Icon(id: "heart", name: "Self-care", words: ["self care", "rest", "relax", "skincare"]),
        Icon(id: "graduationcap", name: "Learning", words: ["study", "studying", "learn", "learning", "course", "homework"]),
        Icon(id: "laptopcomputer", name: "Work", words: ["work", "code", "coding", "project", "meeting", "email"]),
        Icon(id: "phone", name: "Calls", words: ["call", "phone", "dentist call"]),
        Icon(id: "cart", name: "Shopping", words: ["shop", "shopping", "groceries", "buy"]),
        Icon(id: "house", name: "Home", words: ["clean", "cleaning", "laundry", "vacuum", "tidy", "chores"]),
        Icon(id: "banknote", name: "Money", words: ["invoice", "budget", "bills", "pay", "finance", "save money"]),
        Icon(id: "pawprint", name: "Pets", words: ["dog", "cat", "pet", "pets", "vet"]),
        Icon(id: "leaf", name: "Nature", words: ["garden", "gardening", "plants", "plant", "nature"]),
        Icon(id: "music.note", name: "Music", words: ["music", "piano", "guitar", "practice", "sing"]),
        Icon(id: "paintpalette", name: "Creativity", words: ["paint", "painting", "draw", "drawing", "art", "craft"]),
        Icon(id: "person.2", name: "Friends & family", words: ["friends", "family", "visit", "mum", "mom", "dad"]),
        Icon(id: "car", name: "Travel", words: ["drive", "car", "commute", "travel", "trip"]),
        Icon(id: "calendar", name: "Planning", words: ["plan", "planning", "schedule", "review"]),
        Icon(id: "checklist", name: "Checklist", words: []),
        Icon(id: "star", name: "Goals", words: []),
        Icon(id: "flame", name: "Energy", words: []),
        Icon(id: "trophy", name: "Milestones", words: []),
    ]
    static func suggested(for title: String) -> String {
        let text = " " + title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        return all.first { icon in icon.words.contains { text.contains(" " + $0 + " ") } }?.id ?? "checklist"
    }
    static func symbol(_ stored: String, title: String) -> String {
        let value = stored == "automatic" ? suggested(for: title) : stored
        return all.contains { $0.id == value } ? value : "checklist"
    }
}
