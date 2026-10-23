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
    var onSaved: () -> Void = {}
    @State private var text = ""
    @State private var scheduled = true
    @State private var selectedDay = Date.now
    @State private var selectedListID: UUID?
    @State private var error: String?
    @State private var confirmConflict = false
    @State private var conflictTitles: [String] = []
    @State private var keepAddingAfterConflict = false
    @State private var addedCount = 0
    @State private var lastAdded: String?
    @State private var focused = false

    private var defaultDay: DefaultDay {
        scheduled ? .day(PlannerLogic.dayKey(selectedDay)) : .undated
    }
    private var result: QuickAddResult { QuickAdd.parse(text, defaultDay: defaultDay) }
    private var preview: String {
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
                    if let lastAdded {
                        Label("Added “\(lastAdded)”", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(accent.text).lineLimit(2)
                            .accessibilityIdentifier("quick-add-receipt")
                    }
                    if fromList { Toggle("Choose a day", isOn: $scheduled) }
                    if scheduled {
                        DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
                            .accessibilityIdentifier("quick-add-day")
                    }
                    Picker("List", selection: $selectedListID) {
                        Text("Inbox").tag(nil as UUID?)
                        Text("Someday").tag(Optional(TodayRules.somedayID))
                        ForEach(lists.filter { $0.id != TodayRules.somedayID }) { list in
                            Text(list.name).tag(Optional(list.id))
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Return adds this item and starts another. Save adds it and closes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("You can also type a day: “Call dentist tomorrow at 9am”.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(CGFloat(DesignTokens.screenPadding))
            }
            .background(Color.orbitSurface)
            .tint(accent.fill).navigationTitle(result.kind == .habit ? "New habit" : "New task").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(addedCount == 0 ? "Cancel" : "Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(result.title.isEmpty) }
                }
                .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                    Button("Save Anyway") { save(allowConflict: true, keepAdding: keepAddingAfterConflict) }; Button("Change Time", role: .cancel) {}
                } message: { Text(conflictTitles.joined(separator: ", ")) }
                .onChange(of: selectedListID) { _, id in if id == TodayRules.somedayID { scheduled = false } }
                .onChange(of: scheduled) { _, on in if on && selectedListID == TodayRules.somedayID { selectedListID = nil } }
                .sensoryFeedback(.success, trigger: addedCount)
                .onAppear { NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil); text = initialText; selectedDay = initialDate ?? .now; scheduled = !fromList || initialDate != nil; selectedListID = listID; focused = true }.modifier(MutationErrorModifier(error: $error))
        }
        .presentationDetents([.medium, .large])
    }

    private func save(allowConflict: Bool = false, keepAdding: Bool = false) {
        let result = self.result
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
                lastAdded = result.title
                text = ""
                focused = true
            } else {
                dismiss()
            }
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

/// Intercept Return before UIKit ends editing. Keeping the same first responder makes
/// repeated entry work for both the software keyboard and a hardware Return key.
struct CaptureTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var identifier = "task-title-input"
    var placeholder = "What do you need to do?"
    var minimumHeight: CGFloat = 0
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> Input {
        let field = Input()
        field.placeholder = placeholder
        field.accessibilityIdentifier = identifier
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .next
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: Input, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.wantsFocus = focused
        if focused {
            if field.window != nil && !field.isFirstResponder { field.becomeFirstResponder() }
        } else if field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Input, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: max(minimumHeight, uiView.intrinsicContentSize.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Input: UITextField {
        var wantsFocus = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && wantsFocus && !isFirstResponder { becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CaptureTextField
        init(parent: CaptureTextField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.focused { parent.focused = true }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.focused { parent.focused = false }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            // An empty or invalid draft also keeps editing; the save routine validates it.
            return false
        }
    }
}
