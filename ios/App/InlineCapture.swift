import SwiftUI
import SwiftData

/// Capture on Today; advanced options use the same parser and save path. The field grows as you type,
/// and past `NoteRules.threshold` (or with a line break) the text becomes a note instead of a task.
struct InlineCapture: View {
    @Environment(\.modelContext) private var context
    @Environment(\.orbitAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var focused = false
    @State private var options = false
    @State private var saving = false
    @State private var error: String?
    @State private var conflicts: [String] = []
    @State private var confirmConflict = false
    private var result: QuickAddResult { QuickAdd.parse(text) }
    private var isNote: Bool { NoteRules.isNote(text) }
    private var preview: String { isNote ? "Note · Notes" : QuickAdd.describe(result) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if focused { dismissKeyboard() }
                    else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = true }
                    else { save() }
                } label: {
                    Image(systemName: focused ? "chevron.down" : "plus").font(.system(size: 20)).frame(width: 44, height: 44)
                }.accessibilityLabel(focused ? "Dismiss keyboard" : "Add a task").disabled(saving)
                CaptureTextField(text: $text, focused: $focused, identifier: "inline-task-input", placeholder: "Add a task · gym tomorrow 6pm", minimumHeight: 44) { save() }
                DictationButton(text: $text)
                Button { options = true } label: { Image(systemName: "calendar.badge.clock").font(.system(size: 20)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Task options").accessibilityHint("Choose a date or list before adding")
            }.padding(.trailing, 6).padding(.vertical, 4).frame(minHeight: 52).orbitSurface(radius: CGFloat(DesignTokens.radiusInput))
            // The chip belongs to the keyboard: it leaves when the keyboard is swiped away.
            if focused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PreviewChip(text: preview)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }.tint(accent.text)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .orbit, value: focused)
            .animation(reduceMotion ? nil : .orbit, value: isNote)
            .onDisappear { dismissKeyboard() }
            .sheet(isPresented: $options) { QuickCapture(initialText: text, onSaved: { text = "" }) }
            .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                Button("Add anyway") { save(allowConflict: true) }
                Button("Change time", role: .cancel) {}
            } message: { Text(conflicts.joined(separator: ", ")) }
            .modifier(MutationErrorModifier(error: $error))
    }
    private func dismissKeyboard() {
        focused = false
        NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil)
    }
    private func save(allowConflict: Bool = false) {
        // Return on an empty field means the person is done adding.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { dismissKeyboard(); return }
        if isNote { saveNote(); return }
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
            text = ""; focused = true
            saving = false
            Task {
                if draft.time != nil { _ = await NotificationScheduler.shared.requestIfUndecided() }
                do { try await refreshReminders(context) } catch { self.error = "Item added, but reminders could not update: \(error.localizedDescription)" }
            }
        } catch { context.rollback(); saving = false; self.error = error.localizedDescription }
    }
    private func saveNote() {
        guard !saving else { return }
        NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil)
        do { try QuickAddSaver.saveNote(text, in: context); text = ""; focused = true }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
