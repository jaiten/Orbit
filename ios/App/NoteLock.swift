import SwiftUI
import SwiftData
import LocalAuthentication

/// Locked notes and locked note sections open with Face ID, Touch ID or the iPhone passcode (Windows uses
/// one notes password instead). Unlocking lasts until the app leaves the foreground or Lock Now is chosen.
/// Hidden sections need no unlocking: their pages show without titles or text in lists and search.
@MainActor final class NoteLock: ObservableObject {
    static let shared = NoteLock()
    @Published private(set) var unlocked = false

    /// Asks for Face ID or the passcode unless already unlocked. Returns whether locked content may show.
    @discardableResult func unlock(reason: String = "Unlock your locked notes") async -> Bool {
        if unlocked { return true }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var problem: NSError?
        // Without a passcode there is nothing to check against; locks then only hide content from lists.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            unlocked = true
            return true
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            withAnimation(.orbit) { unlocked = ok }
            return ok
        } catch { return false }
    }
    func lock() { withAnimation(.orbit) { unlocked = false } }

    /// Whether a note sits behind the lock: locked itself, or in a locked section.
    static func isLocked(_ note: PlannerTask, lists: [TaskList]) -> Bool {
        note.locked == true || (note.listID.flatMap { id in lists.first { $0.id == id } }?.locked == true)
    }
    /// A page in a hidden section.
    static func isHidden(_ note: PlannerTask, lists: [TaskList]) -> Bool {
        note.listID.flatMap { id in lists.first { $0.id == id } }?.hidden == true
    }
    func isSealed(_ note: PlannerTask, lists: [TaskList]) -> Bool { !unlocked && Self.isLocked(note, lists: lists) }
}

/// The page shown in place of a locked note until it is unlocked.
struct LockedNotePlaceholder: View {
    let title: String
    @ObservedObject private var lock = NoteLock.shared
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title.isEmpty ? "Locked note" : title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text("This note is locked.").foregroundStyle(.secondary)
            Button("Unlock") { Task { await lock.unlock() } }.buttonStyle(.borderedProminent).accessibilityIdentifier("unlock-note")
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await lock.unlock() }
    }
}
