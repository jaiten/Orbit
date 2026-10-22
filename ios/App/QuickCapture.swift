import SwiftUI
import SwiftData

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
    @State private var text = ""
    @State private var error: String?
    @State private var confirmConflict = false
    @State private var conflictTitles: [String] = []
    @State private var keepAddingAfterConflict = false
    @State private var addedCount = 0
    @State private var lastAdded: String?
    @FocusState private var focused: Bool

    private var defaultDay: DefaultDay {
        if fromList { return .undated }
        if let initialDate, !Calendar.current.isDateInToday(initialDate) { return .day(PlannerLogic.dayKey(initialDate)) }
        return .today
    }
    private var result: QuickAddResult { QuickAdd.parse(text, defaultDay: defaultDay) }
    private var preview: String {
        var value = QuickAdd.describe(result)
        if !value.isEmpty, result.kind == .task, !result.someday, result.list == nil, let name = contextListName { value += " · " + name }
        return value
    }
    private var contextListName: String? {
        listID == TodayRules.somedayID ? "Someday" : lists.first { $0.id == listID }?.name
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                Eyebrow(text: "Quick add")
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    TextField("What do you need to do?", text: $text)
                        .font(.title3).focused($focused).accessibilityIdentifier("task-title-input")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { save(keepAdding: true) }
                }
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(DayTheme.canvas(scheme), in: RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusInput), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusInput), style: .continuous)
                    .strokeBorder(focused ? accent.text : Color.orbitLine, lineWidth: focused ? 2 : 1))
                PreviewChip(text: preview, identifier: "quick-add-preview").frame(minHeight: 34, alignment: .leading)
                Text("Return adds this item and starts another. Save adds it and closes.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Try “gym tomorrow 6pm”, “read every day” or “#work”.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let lastAdded {
                    Label("Added “\(lastAdded)”", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(accent.text).lineLimit(2)
                        .accessibilityIdentifier("quick-add-receipt")
                }
                Spacer(minLength: 0)
            }
            .padding(CGFloat(DesignTokens.screenPadding))
            .background(Color.orbitSurface)
            .tint(accent.fill).navigationTitle("New Item").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(addedCount == 0 ? "Cancel" : "Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(result.title.isEmpty) }
                }
                .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                    Button("Save Anyway") { save(allowConflict: true, keepAdding: keepAddingAfterConflict) }; Button("Change Time", role: .cancel) {}
                } message: { Text(conflictTitles.joined(separator: ", ")) }
                .sensoryFeedback(.success, trigger: addedCount)
                .onAppear { focused = true }.modifier(MutationErrorModifier(error: $error))
        }
        .presentationDetents([.medium, .large])
    }

    private func save(allowConflict: Bool = false, keepAdding: Bool = false) {
        let result = self.result
        guard !result.title.isEmpty else { return }
        do {
            if !allowConflict, result.kind == .task, result.time != nil, let start = result.date.flatMap({ QuickAdd.start(of: $0, time: result.time) }) {
                conflictTitles = CalendarBridge.shared.conflictTitles(start: start, duration: 30, excluding: nil, tasks: try context.fetch(FetchDescriptor<PlannerTask>()))
                if !conflictTitles.isEmpty { keepAddingAfterConflict = keepAdding; confirmConflict = true; return }
            }
            try QuickAddSaver.save(result, listID: listID, in: context)
            Task {
                // The first item with a time is the moment to ask about notifications.
                if result.time != nil { _ = await NotificationScheduler.shared.requestIfUndecided() }
                try? await refreshReminders(context)
            }
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
