import SwiftUI
import SwiftData

/// Capture stays on Today; advanced options use the same parser and save path.
struct InlineCapture: View {
    @Environment(\.modelContext) private var context
    @Environment(\.orbitAccent) private var accent
    @State private var text = ""
    @State private var focused = false
    @State private var options = false
    @State private var saving = false
    @State private var receipt: String?
    @State private var error: String?
    @State private var conflicts: [String] = []
    @State private var confirmConflict = false
    private var result: QuickAddResult { QuickAdd.parse(text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = true } else { save() } } label: {
                    Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44)
                }.accessibilityLabel("Add a task").disabled(saving)
                CaptureTextField(text: $text, focused: $focused, identifier: "inline-task-input", placeholder: "Add a task") { save() }
                DictationButton(text: $text)
                Button { options = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 20)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Task options").accessibilityHint("Choose a date or list before adding")
            }.padding(.trailing, 6).frame(minHeight: 52).orbitSurface()
            if !text.isEmpty { PreviewChip(text: QuickAdd.describe(result)) }
            if let receipt { Text(receipt).font(.footnote).foregroundStyle(accent.text).accessibilityIdentifier("inline-add-receipt") }
        }.tint(accent.text)
            .sheet(isPresented: $options) { QuickCapture(initialText: text, onSaved: { text = "" }) }
            .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                Button("Add anyway") { save(allowConflict: true) }
                Button("Change time", role: .cancel) {}
            } message: { Text(conflicts.joined(separator: ", ")) }
            .modifier(MutationErrorModifier(error: $error))
    }
    private func save(allowConflict: Bool = false) {
        let draft = result
        guard !saving, !draft.title.isEmpty else { return }
        NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil)
        do {
            if !allowConflict, draft.kind == .task, draft.time != nil,
               let start = draft.date.flatMap({ QuickAdd.start(of: $0, time: draft.time) }) {
                conflicts = CalendarBridge.shared.conflictTitles(start: start, duration: 30, excluding: nil, tasks: try context.fetch(FetchDescriptor<PlannerTask>()))
                if !conflicts.isEmpty { confirmConflict = true; return }
            }
            saving = true
            try QuickAddSaver.save(draft, in: context)
            text = ""; receipt = "Added “\(draft.title)”"; focused = true
            saving = false
            Task {
                if draft.time != nil { _ = await NotificationScheduler.shared.requestIfUndecided() }
                do { try await refreshReminders(context) } catch { self.error = "Item added, but reminders could not update: \(error.localizedDescription)" }
            }
        } catch { context.rollback(); saving = false; self.error = error.localizedDescription }
    }
}
