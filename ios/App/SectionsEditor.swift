import SwiftUI
import SwiftData

/// Sections (stored as lists) group notes and tasks. Someday is built in.
struct ListsView: View {
    var categoryMode = false
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var name = ""
    @FocusState private var naming: Bool
    @State private var error: String?
    @State private var pendingDelete: TaskList?
    private var editable: [TaskList] { lists.filter { categoryMode ? $0.isTaskCategory : $0.isNoteSection } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(editable) { list in
                        if list.id == TodayRules.somedayID {
                            Label("Someday", systemImage: "moon.zzz").frame(minHeight: 44).deleteDisabled(true)
                        } else {
                            ListNameRow(list: list).frame(minHeight: 44)
                        }
                    }
                        .onMove(perform: moveLists)
                        .onDelete { indices in pendingDelete = indices.first.map { editable[$0] }; if pendingDelete?.id == TodayRules.somedayID { pendingDelete = nil } }
                } header: { Text(categoryMode ? "Categories" : "Sections") }
                Section {
                    HStack(spacing: 12) {
                        TextField(categoryMode ? "New category name" : "New section name", text: $name)
                            .focused($naming).accessibilityIdentifier("new-list-name").onSubmit(addGroup)
                        Button(action: addGroup) { Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                            .buttonStyle(.plain).foregroundStyle(.white).background(accent.fill, in: Circle())
                            .accessibilityLabel(categoryMode ? "Add category" : "Add Section")
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                }
            }.environment(\.editMode, .constant(.active))
                .scrollDismissesKeyboard(.interactively)
                .onAppear { if categoryMode { do { try TodayRules.ensureSomeday(context) } catch { self.error = error.localizedDescription } } }.tint(accent.fill).navigationTitle(categoryMode ? "Categories" : "Edit Sections")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { naming = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .modifier(MutationErrorModifier(error: $error))
                .confirmationDialog("Delete this section? Its notes and tasks are kept, without a section.", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                    Button("Delete section", role: .destructive) {
                        guard let list = pendingDelete else { return }
                        do {
                            let id = list.id
                            let tasks = try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.listID == id }))
                            for task in tasks where task.note != categoryMode { task.listID = nil; task.updatedAt = .now }
                            if list.kind == nil { list.kind = categoryMode ? "notes" : "tasks"; list.updatedAt = .now } else { context.delete(list) }; try Mutations.save(context); pendingDelete = nil
                        } catch { context.rollback(); self.error = error.localizedDescription }
                    }
                }
        }
    }
    private func addGroup() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(TaskList(name: trimmed, sortOrder: (editable.map(\.sortOrder).max() ?? -1) + 1, kind: categoryMode ? "tasks" : "notes"))
        do { try Mutations.save(context); name = "" } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func moveLists(from source: IndexSet, to destination: Int) {
        var ordered = editable
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, list) in ordered.enumerated() { list.sortOrder = index; list.updatedAt = .now }
        do { try Mutations.save(context) } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct ListNameRow: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    let list: TaskList
    @State private var name = ""
    @FocusState private var naming: Bool
    @State private var error: String?
    var body: some View {
        HStack {
            Circle().fill(DayTheme.color(list.color)).frame(width: 10, height: 10)
            TextField("Section name", text: $name).onSubmit(saveName)
            if name != list.name {
                Button(action: saveName) { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Save section name")
            }
        }.onAppear { name = list.name }.modifier(MutationErrorModifier(error: $error))
    }
    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { name = list.name; return }
        list.name = trimmed; list.updatedAt = .now
        do { try Mutations.save(context) } catch { self.error = error.localizedDescription }
    }
}
