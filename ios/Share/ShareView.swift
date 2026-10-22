import SwiftUI
import SwiftData

/// Quick add, prefilled with what was shared. The web address goes into the task's notes.
/// It is saved to the shared App Group store and outbox, and syncs the next time Orbit opens.
struct ShareView: View {
    let shared: SharedContent
    var done: () -> Void
    var cancel: () -> Void
    @State private var text: String
    @State private var error: String?
    private var accent: Color { DayTheme.accent }

    init(shared: SharedContent, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.shared = shared; self.done = done; self.cancel = cancel
        _text = State(initialValue: shared.text)
    }
    private var result: QuickAddResult { QuickAdd.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $text, axis: .vertical).font(.title3)
                    let preview = QuickAdd.describe(result)
                    if !preview.isEmpty {
                        Text(preview).font(.footnote.weight(.medium)).foregroundStyle(accent)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(accent.opacity(0.12), in: Capsule())
                    }
                    if let url = shared.url { Text(url.absoluteString).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                } footer: { Text("Add a day such as “tomorrow”, or “someday” to save it without a date. Changes sync the next time you open Orbit.") }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .tint(accent).navigationTitle("Add to Orbit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(result.title.isEmpty) }
            }
        }
    }

    private func save() {
        do {
            let context = ModelContext(try Persistence.makeContainer())
            context.autosaveEnabled = false
            try QuickAddSaver.save(result, notes: shared.url?.absoluteString ?? "", in: context)
            done()
        } catch { self.error = error.localizedDescription }
    }
}
