import SwiftUI
import SwiftData

/// Lets global transient controls (Undo) clear the docked capture bar, including Dynamic Type and chips.
struct CaptureDockHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Docks a capture bar above the tab bar and keyboard, over a fade of the page colour.
    func captureDock<Bar: View>(_ scheme: ColorScheme, @ViewBuilder bar: () -> Bar) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            bar()
                .padding(.horizontal, CGFloat(DesignTokens.screenPadding))
                .padding(.vertical, 8)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
                .background {
                    GeometryReader { geometry in Color.clear.preference(key: CaptureDockHeight.self, value: geometry.size.height) }
                }
                .background {
                    LinearGradient(colors: [DayTheme.canvas(scheme).opacity(0), DayTheme.canvas(scheme), DayTheme.canvas(scheme)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

/// Capture docked at the bottom of Today; advanced options use the same parser and save path. The field
/// grows as you type, and past `NoteRules.threshold` (or with a line break) the text becomes a note.
/// With `notesOnly` (on Notes) everything typed becomes a note.
struct InlineCapture: View {
    var notesOnly = false
    var habitsOnly = false
    var defaultDay: DefaultDay = .today
    var listID: UUID? = nil
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
    private var result: QuickAddResult {
        var parsed = QuickAdd.parse(text, defaultDay: defaultDay)
        if habitsOnly { parsed.kind = .habit; parsed.schedule = parsed.schedule ?? "DAILY" }
        return parsed
    }
    private var isNote: Bool { notesOnly || (!habitsOnly && NoteRules.isNote(text)) }
    private var preview: String { isNote ? "Note · All notes" : QuickAdd.describe(result) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The chip belongs to the keyboard: it leaves when the keyboard is swiped away.
            if focused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { options = true } label: { PreviewChip(text: preview, identifier: "inline-preview-text") }.buttonStyle(.plain).accessibilityLabel(preview).accessibilityHint("Change date and time").accessibilityIdentifier("quick-add-preview")
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if focused { dismissKeyboard() }
                    else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = true }
                    else { save() }
                } label: {
                    Image(systemName: focused ? "chevron.down" : "plus").font(.system(size: 20)).frame(width: 44, height: 44)
                }.accessibilityLabel(focused ? "Dismiss keyboard" : notesOnly ? "Add a note" : "Add a task").disabled(saving)
                CaptureTextField(text: $text, focused: $focused, identifier: notesOnly ? "note-capture-input" : "inline-task-input", placeholder: notesOnly ? "Write a note" : habitsOnly ? "Add a habit" : "Add a task · gym tomorrow 6pm", minimumHeight: 44) { save() }
                DictationButton(text: $text)
                if !notesOnly {
                    Button { options = true } label: { Image(systemName: "calendar.badge.clock").font(.system(size: 20)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Task options").accessibilityHint("Choose a date or list before adding")
                }
            }.padding(.trailing, 6).padding(.vertical, 4).frame(minHeight: 52).orbitSurface(radius: CGFloat(DesignTokens.radiusInput))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
        }.tint(accent.text)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .orbit, value: focused)
            .onDisappear { dismissKeyboard() }
            .sheet(isPresented: $options) { QuickCapture(listID: listID, fromList: listID != nil || defaultDay == .undated, initialText: text, habitsOnly: habitsOnly, onSaved: { text = "" }).presentationDragIndicator(.visible) }
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
            try QuickAddSaver.save(draft, listID: listID, in: context)
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
