import SwiftUI
import SwiftData
import UIKit
import UIKit.UIGestureRecognizerSubclass

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

/// A tap that never blocks anything: it ends when the finger lifts without having moved, and fails as soon
/// as the touch travels (a swipe or a scroll), so swiping away the Undo note or scrolling keeps the keyboard.
final class PassiveTapRecognizer: UIGestureRecognizer {
    private var start: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first else { state = .failed; return }
        start = touch.location(in: view)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let touch = touches.first else { return }
        let point = touch.location(in: view)
        if hypot(point.x - start.x, point.y - start.y) > 10 { state = .failed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = state == .possible ? .ended : .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func reset() { start = nil }
}

/// Closes the docked capture (and its keyboard) when the person taps anything else in the app: a row,
/// a card, a tab. The tap still does what it would have done; only taps on the capture itself (and the
/// strip just above it, where its preview chip and the Undo note sit), or in another text field, are left
/// alone. One recognizer on the window, active only while a capture is open.
@MainActor final class CaptureOutsideTap: NSObject, UIGestureRecognizerDelegate {
    static let shared = CaptureOutsideTap()
    /// The open capture, in window coordinates, and what to do when something else is touched.
    var captureFrame: CGRect = .zero
    var onOutside: (() -> Void)?
    private weak var installed: UIWindow?
    private lazy var recognizer: PassiveTapRecognizer = {
        let tap = PassiveTapRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        return tap
    }()
    func activate(_ onOutside: @escaping () -> Void) {
        self.onOutside = onOutside
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow), installed !== window else { return }
        installed?.removeGestureRecognizer(recognizer)
        window.addGestureRecognizer(recognizer)
        installed = window
    }
    func deactivate() { onOutside = nil }
    @objc private func tapped() { onOutside?() }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard onOutside != nil, let window = touch.window else { return false }
        // The capture, plus the strip above it where its chip and the Undo note show.
        let kept = CGRect(x: captureFrame.minX - 4, y: captureFrame.minY - 76, width: captureFrame.width + 8, height: captureFrame.height + 80)
        if kept.contains(touch.location(in: window)) { return false }
        // Another text field takes focus by itself.
        var view = touch.view
        while let current = view { if current is UITextView || current is UITextField { return false }; view = current.superview }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Capture docked at the bottom of Today, Tasks and Habits; advanced options use the same parser and save
/// path. The field grows as you type, and past `NoteRules.threshold` characters, `NoteRules.wordLimit` words
/// (not counting date and time words) or a line break the text becomes a note: the bar unfolds into a note
/// card in place, with a title above and the text as its body, without the keyboard or caret moving.
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
    @State private var noteTitle = ""
    @State private var focused = false
    @State private var options = false
    @State private var saving = false
    @State private var error: String?
    @State private var conflicts: [String] = []
    /// Where the bar is on screen, so touches on it don't count as touching something else.
    @State private var barFrame: CGRect = .zero
    @State private var confirmConflict = false
    private var result: QuickAddResult {
        var parsed = QuickAdd.parse(text, defaultDay: defaultDay)
        if habitsOnly { parsed.kind = .habit; parsed.schedule = parsed.schedule ?? "DAILY" }
        return parsed
    }
    private var isNote: Bool { notesOnly || NoteRules.isNote(text) || (!noteTitle.isEmpty && !text.isEmpty) }
    /// Outside Notes, a capture that has become a note shows as a note card.
    private var noteCard: Bool { !notesOnly && isNote }
    private var preview: String {
        if isNote { return "Note · General" }
        var value = QuickAdd.describe(result)
        guard !value.isEmpty else { return value }
        if listID == nil, let suggested = CategorySuggestion.suggest(for: result, in: context) { value += " · " + suggested.name }
        if result.kind == .task, TaskProgress.learned(for: result.title, in: context) == .auto { value += " · Start & finish" }
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The chip belongs to the keyboard: it leaves when the keyboard is swiped away. The note card
            // says what it is itself.
            if focused && !noteCard && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { options = true } label: { PreviewChip(text: preview, identifier: "inline-preview-text") }.buttonStyle(.plain).accessibilityLabel(preview).accessibilityHint("Change date and time").accessibilityIdentifier("quick-add-preview")
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 0) {
                if noteCard { noteHeader.transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)) }
                // Icons sit in the middle of the first line however tall the text grows.
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        if focused { dismissKeyboard() }
                        else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = true }
                        else { save() }
                    } label: {
                        // The arrow swaps quickly, so it never lingers after the bar has gone down.
                        Image(systemName: focused ? "chevron.down" : "plus").font(.system(size: 20)).frame(width: 44, height: lineHeight)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.1), value: focused)
                    }.accessibilityLabel(focused ? "Dismiss keyboard" : notesOnly ? "Add a note" : "Add a task").disabled(saving)
                    // The same field throughout, so focus, the caret and the keyboard stay as the card unfolds.
                    CaptureTextField(text: $text, focused: $focused, identifier: notesOnly ? "note-capture-input" : "inline-task-input",
                                     placeholder: notesOnly ? "Write a note" : habitsOnly ? "Add a habit" : "Add a task · gym tomorrow 6pm",
                                     minimumHeight: noteCard ? 110 : 44, maximumLines: noteCard ? 10 : 6, allowsNewlines: noteCard,
                                     textStyle: noteCard ? .body : .title3) { save() }
                    DictationButton(text: $text).frame(height: lineHeight)
                    if !notesOnly && !noteCard {
                        Button { options = true } label: { Image(systemName: "calendar").font(.system(size: 20)).frame(width: 44, height: lineHeight) }
                            .accessibilityLabel("Task options").accessibilityHint("Choose a date or list before adding")
                    }
                }
                if noteCard {
                    HStack {
                        Spacer()
                        Button("Save") { saveNote() }.font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).frame(minHeight: 36)
                            .background(accent.fill.opacity(0.14), in: Capsule())
                            .accessibilityIdentifier("save-capture-note")
                    }.padding(.bottom, 6).transition(.opacity)
                }
            }.padding(.trailing, noteCard ? 6 : 0).padding(.vertical, 4).frame(minHeight: 52)
                .orbitSurface(radius: noteCard ? 18 : CGFloat(DesignTokens.radiusInput))
                .shadow(color: .black.opacity(noteCard ? 0.14 : 0.06), radius: noteCard ? 24 : 12, y: noteCard ? 8 : 3)
        }.tint(accent.text)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .orbit, value: focused)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82), value: noteCard)
            .sensoryFeedback(.impact(weight: .light), trigger: noteCard) { _, now in now }
            .background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        barFrame = frame
                        if focused { CaptureOutsideTap.shared.captureFrame = frame }
                    }
                }
            }
            .onChange(of: focused) { _, now in
                if now {
                    CaptureOutsideTap.shared.captureFrame = barFrame
                    CaptureOutsideTap.shared.activate { dismissKeyboard() }
                } else { CaptureOutsideTap.shared.deactivate() }
            }
            .onDisappear {
                if focused { CaptureOutsideTap.shared.deactivate() }
                dismissKeyboard()
            }
            .sheet(isPresented: $options) { QuickCapture(listID: listID, fromList: listID != nil || defaultDay == .undated, initialText: text, habitsOnly: habitsOnly, onSaved: { text = "" }).presentationDragIndicator(.visible) }
            .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                Button("Add anyway") { save(allowConflict: true) }
                Button("Change time", role: .cancel) {}
            } message: { Text(conflicts.joined(separator: ", ")) }
            .modifier(MutationErrorModifier(error: $error))
    }
    /// The height of one line of the field, so the icons beside it are centred on the first line.
    private var lineHeight: CGFloat {
        max(44, UIFont.preferredFont(forTextStyle: noteCard ? .body : .title3).lineHeight + 22)
    }
    /// Above a capture that has become a note: where it goes, an optional title and × to throw it away.
    /// Save sits at the bottom right. Return in the text is a new line once it is a note.
    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("New note · General", systemImage: "square.and.pencil").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                // Throws the draft away, for when the keyboard is down and the note isn't wanted.
                Button { discardNote() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 32, height: 32).background(Color.secondary.opacity(0.12), in: Circle())
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Discard note").accessibilityIdentifier("discard-capture-note")
            }
            TextField("Title", text: $noteTitle).font(.title3.weight(.semibold))
                .submitLabel(.next).onSubmit { focused = true }
                .accessibilityIdentifier("capture-note-title")
        }.padding(.leading, 16).padding(.trailing, 4).padding(.top, 8)
    }
    private func discardNote() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) {
            text = ""; noteTitle = ""
        }
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
        do { try QuickAddSaver.saveNote(text, title: noteTitle, in: context); text = ""; noteTitle = ""; focused = true }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
