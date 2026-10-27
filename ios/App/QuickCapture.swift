import SwiftUI
import SwiftData
import UIKit

/// One rounded field, as on the website. The chip shows what will be created ("Task · Tomorrow · 6:00 PM")
/// before saving; details can be added afterwards by opening the item.
struct QuickCapture: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    /// The day being viewed (Calendar); nil means today.
    var initialDate: Date? = nil
    /// Adding from Lists: the item lands in this list, undated unless the text names a day.
    var listID: UUID? = nil
    var fromList = false
    var initialText = ""
    var habitsOnly = false
    var onSaved: () -> Void = {}
    @State private var text = ""
    @State private var scheduled = true
    @State private var editedTime = false
    @State private var hasTime = false
    @State private var time = Date.now
    @State private var editedDay = false
    @State private var ready = false
    @State private var selectedDay = Date.now
    @State private var selectedListID: UUID?
    @State private var error: String?
    @State private var confirmConflict = false
    @State private var conflictTitles: [String] = []
    @State private var keepAddingAfterConflict = false
    @State private var addedCount = 0
    @State private var focused = false

    private var defaultDay: DefaultDay {
        scheduled ? .day(PlannerLogic.dayKey(selectedDay)) : .undated
    }
    private var result: QuickAddResult {
        var parsed = QuickAdd.parse(text, defaultDay: defaultDay)
        if habitsOnly { parsed.kind = .habit; parsed.schedule = parsed.schedule ?? "DAILY" }
        if editedDay && parsed.kind == .task { parsed.date = scheduled ? PlannerLogic.dayKey(selectedDay) : nil; parsed.someday = false }
        if editedTime { parsed.time = hasTime ? Calendar.current.component(.hour, from: time) * 60 + Calendar.current.component(.minute, from: time) : nil }
        return parsed
    }
    private var isNote: Bool { !habitsOnly && NoteRules.isNote(text) }
    private var preview: String {
        if isNote { return "Note · " + (contextListName ?? "Notes") }
        var value = QuickAdd.describe(result)
        if !value.isEmpty, result.kind == .task, !result.someday, result.list == nil, let name = contextListName { value += " · " + name }
        return value
    }
    private var contextListName: String? {
        if selectedListID == TodayRules.somedayID && result.date != nil { return nil }
        return selectedListID == TodayRules.somedayID ? "Someday" : lists.first { $0.id == selectedListID }?.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                    Eyebrow(text: "Quick add")
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                        CaptureTextField(text: $text, focused: $focused) { save(keepAdding: true) }
                        DictationButton(text: $text)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 52)
                    .background(DayTheme.canvas(scheme), in: RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusInput), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusInput), style: .continuous)
                        .strokeBorder(focused ? accent.text : Color.orbitLine, lineWidth: focused ? 2 : 1))
                    PreviewChip(text: preview, identifier: "quick-add-preview").frame(minHeight: 34, alignment: .leading)
                    if fromList { Toggle("Choose a day", isOn: $scheduled) }
                    if scheduled {
                        DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
                            .accessibilityIdentifier("quick-add-day")
                    }
                    Toggle(result.kind == .habit ? "Reminder time" : "Time", isOn: $hasTime).onChange(of: hasTime) { _, _ in editedTime = true }
                    if hasTime { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).onChange(of: time) { _, _ in editedTime = true } }
                    if initialDate == nil && !habitsOnly {
                    Picker("Category", selection: $selectedListID) {
                        Text("No category").tag(nil as UUID?)
                        Text("Someday").tag(Optional(TodayRules.somedayID))
                        ForEach(lists.filter { $0.id != TodayRules.somedayID }) { list in
                            Text(list.name).tag(Optional(list.id))
                        }
                    }
                    .pickerStyle(.menu)
                    }
                    Text("Return adds this item and starts another; Return on an empty line closes the keyboard. Long text becomes a note.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("You can also type a day: “Call dentist tomorrow at 9am”.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(CGFloat(DesignTokens.screenPadding))
            }
            .background(Color.orbitSurface)
            .tint(accent.fill).navigationTitle(isNote ? "New note" : result.kind == .habit ? "New habit" : "New task").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(addedCount == 0 ? "Cancel" : "Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(result.title.isEmpty && !isNote) }
                }
                .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                    Button("Save Anyway") { save(allowConflict: true, keepAdding: keepAddingAfterConflict) }; Button("Change Time", role: .cancel) {}
                } message: { Text(conflictTitles.joined(separator: ", ")) }
                .onChange(of: selectedDay) { _, _ in if ready { editedDay = true } }
                .onChange(of: selectedListID) { _, id in if id == TodayRules.somedayID { scheduled = false } }
                .onChange(of: scheduled) { _, on in if on && selectedListID == TodayRules.somedayID { selectedListID = nil } }
                .onAppear { NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil); text = initialText; selectedDay = initialDate ?? .now; scheduled = !fromList || initialDate != nil; selectedListID = listID;
                    let parsed = QuickAdd.parse(initialText)
                    hasTime = parsed.time != nil
                    if let minutes = parsed.time { time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now }
                    focused = true; Task { await Task.yield(); ready = true; editedTime = false } }.modifier(MutationErrorModifier(error: $error))
        }
        .presentationDetents([.medium, .large])
    }

    private func save(allowConflict: Bool = false, keepAdding: Bool = false) {
        let result = self.result
        // Return on an empty field means the person is done adding.
        if keepAdding && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = false; return }
        if isNote {
            do {
                try QuickAddSaver.saveNote(text, listID: selectedListID, in: context)
                onSaved(); addedCount += 1
                if keepAdding { text = ""; focused = true } else { dismiss() }
            } catch { context.rollback(); self.error = error.localizedDescription }
            return
        }
        guard !result.title.isEmpty else { return }
        NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil)
        do {
            if !allowConflict, result.kind == .task, result.time != nil, let start = result.date.flatMap({ QuickAdd.start(of: $0, time: result.time) }) {
                conflictTitles = CalendarBridge.shared.conflictTitles(start: start, duration: 30, excluding: nil, tasks: try context.fetch(FetchDescriptor<PlannerTask>()))
                if !conflictTitles.isEmpty { keepAddingAfterConflict = keepAdding; confirmConflict = true; return }
            }
            try QuickAddSaver.save(result, listID: selectedListID, in: context)
            Task {
                // The first item with a time is the moment to ask about notifications.
                if result.time != nil { _ = await NotificationScheduler.shared.requestIfUndecided() }
                try? await refreshReminders(context)
            }
            onSaved()
            addedCount += 1
            if keepAdding {
                text = ""
                focused = true
            } else {
                dismiss()
            }
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

/// A capture field that grows with what is typed, then scrolls. Return submits instead of adding a line
/// (pasted line breaks are kept, which makes the text a note). Keeping the same first responder makes
/// repeated entry work for both the software keyboard and a hardware Return key. Autocorrect,
/// capitalisation and spelling follow the system keyboard settings.
struct CaptureTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var identifier = "task-title-input"
    var placeholder = "What do you need to do?"
    var minimumHeight: CGFloat = 0
    /// Grows up to this many lines, then scrolls.
    var maximumLines = 6
    var allowsNewlines = false
    var onPasteImage: ((UIImage) -> Void)? = nil
    var textStyle: UIFont.TextStyle = .title3
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> Input {
        let field = Input()
        field.placeholder = placeholder
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = placeholder
        field.font = .preferredFont(forTextStyle: textStyle)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .clear
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .default
        field.spellCheckingType = .default
        field.returnKeyType = .next
        field.isScrollEnabled = false
        field.textContainerInset = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        field.textContainer.lineFragmentPadding = 0
        field.delegate = context.coordinator
        field.textChanged()
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: Input, context: Context) {
        context.coordinator.parent = self
        field.onPasteImage = onPasteImage
        // SwiftUI can echo an older binding while UIKit is still processing typing or autocorrect.
        // Accept deliberate external edits, but never replace an active composition or recent UIKit edit.
        if field.text != text, field.markedTextRange == nil,
           text.isEmpty || !field.isFirstResponder || !context.coordinator.recentEdits.contains(text) {
            let selection = field.selectedRange
            field.text = text
            field.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
            field.textChanged()
        }
        field.wantsFocus = focused
        field.scheduleFocusUpdate()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Input, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let lineHeight = uiView.font?.lineHeight ?? 24
        let limit = lineHeight * CGFloat(maximumLines) + uiView.textContainerInset.top + uiView.textContainerInset.bottom
        let scrolls = fitting > limit
        if uiView.isScrollEnabled != scrolls { uiView.isScrollEnabled = scrolls }
        return CGSize(width: width, height: max(minimumHeight, min(fitting, limit)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Input: UITextView {
        var wantsFocus = false
        var onPasteImage: ((UIImage) -> Void)?
        override func paste(_ sender: Any?) {
            if let onPasteImage, let image = UIPasteboard.general.image { onPasteImage(image) }
            else { super.paste(sender) }
        }
        private var focusUpdateScheduled = false
        private let placeholderLabel = UILabel()
        var placeholder = "" {
            didSet { placeholderLabel.text = placeholder }
        }

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            placeholderLabel.textColor = .placeholderText
            placeholderLabel.font = .preferredFont(forTextStyle: .title3)
            placeholderLabel.adjustsFontForContentSizeCategory = true
            placeholderLabel.isAccessibilityElement = false
            addSubview(placeholderLabel)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            placeholderLabel.frame = CGRect(x: textContainerInset.left, y: textContainerInset.top,
                                            width: max(0, bounds.width - textContainerInset.left - textContainerInset.right),
                                            height: font?.lineHeight ?? 24)
        }

        func textChanged() {
            placeholderLabel.font = font
            placeholderLabel.isHidden = !text.isEmpty
            invalidateIntrinsicContentSize()
        }

        // UIKit can synchronously trigger keyboard layout and delegate callbacks here.
        // Wait until SwiftUI has finished updating, and use the latest requested focus.
        func scheduleFocusUpdate() {
            guard !focusUpdateScheduled else { return }
            focusUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusUpdateScheduled = false
                guard self.window != nil else { return }
                if self.wantsFocus && !self.isFirstResponder { self.becomeFirstResponder() }
                else if !self.wantsFocus && self.isFirstResponder { self.resignFirstResponder() }
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleFocusUpdate()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CaptureTextField
        var recentEdits: [String] = []
        init(parent: CaptureTextField) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? Input)?.textChanged()
            let value = textView.text ?? ""
            recentEdits.append(value)
            if recentEdits.count > 24 { recentEdits.removeFirst() }
            parent.text = value
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused { parent.focused = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused { parent.focused = false }
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return submits; the save routine validates the draft (an empty one closes the keyboard).
            guard text == "\n", !parent.allowsNewlines else { return true }
            parent.onSubmit()
            return false
        }
    }
}
