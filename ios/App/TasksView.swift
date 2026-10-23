import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @State private var error: String?
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var search = ""
    @State private var listID: UUID?
    @State private var collapsed: Set<TaskDateGroup> = [.completed]
    @State private var creatingList = false
    @State private var newListName = ""
    @AppStorage("compactRows") private var compactRows = false
    @State private var adding = false
    @State private var editing: PlannerTask?
    @State private var manageLists = false
    private var filtered: [PlannerTask] {
        tasks.filter { task in
            (listID == nil || task.listID == listID) &&
            (search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.tags.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(DesignTokens.spaceL)) {
                PageHeader(eyebrow: "Organize", title: "Lists") {
                    Button { manageLists = true } label: {
                        Text("Edit Lists").padding(.horizontal, 14).frame(minHeight: 44)
                    }
                    Button { creatingList = true } label: { Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("New list")
                }.padding(.horizontal, 20).padding(.top, 8)
                List {
                    Section {
                        TextField("Search tasks", text: $search).textInputAutocapitalization(.never)
                        AccentPicker(title: "List", selection: $listID, choices: [(nil as UUID?, "All Tasks"), (Optional(TodayRules.somedayID), "Someday")] + lists.filter { $0.id != TodayRules.somedayID }.map { (Optional($0.id), $0.name) })
                    }
                    Section {
                        Button("Add a task", systemImage: "plus.circle.fill") { adding = true }.accessibilityLabel("New task")
                    }
                    if filtered.isEmpty { ContentUnavailableView("No tasks in this list", systemImage: "checklist") }
                    ForEach(TaskDateGroup.allCases) { group in
                        let items = grouped(group)
                        if !items.isEmpty {
                            Section {
                                if !collapsed.contains(group) {
                                    ForEach(items) { task in
                                        TaskRow(task: task) { editing = task }
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: compactRows ? 2 : 4, leading: 0, bottom: compactRows ? 2 : 4, trailing: 0))
                                    }
                                }
                            } header: {
                                Button {
                                    if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("\(group.rawValue) (\(items.count))").font(.subheadline.weight(.semibold))
                                        Image(systemName: collapsed.contains(group) ? "chevron.right" : "chevron.down").font(.caption.weight(.semibold))
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).textCase(nil)
                                    .accessibilityLabel("\(group.rawValue) (\(items.count))")
                                    .accessibilityValue(collapsed.contains(group) ? "Collapsed" : "Expanded")
                                    .accessibilityHint("Double-tap to " + (collapsed.contains(group) ? "show tasks" : "hide tasks"))
                                    .accessibilityIdentifier("task-group-" + group.id)
                            }

                        }
                    }
                }.listStyle(.insetGrouped).contentMargins(.top, 0, for: .scrollContent).listSectionSpacing(CGFloat(DesignTokens.spaceL)).scrollContentBackground(.hidden).background(DayTheme.canvas(scheme))
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).background(DayTheme.canvas(scheme))
                .tint(accent.fill).navigationTitle("Lists")
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $adding) { QuickCapture(listID: listID, fromList: true) }.sheet(item: $editing) { TaskEditor(task: $0) }
                .sheet(isPresented: $manageLists) { ListsView() }
                .alert("New list", isPresented: $creatingList) {
                    TextField("List name", text: $newListName)
                    Button("Cancel", role: .cancel) { newListName = "" }
                    Button("Create list") { createList() }.disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .modifier(MutationErrorModifier(error: $error))
        }
    }
    private func grouped(_ group: TaskDateGroup) -> [PlannerTask] {
        filtered.filter {
            TaskDateGroup.group(day: $0.day, someday: $0.listID == TodayRules.somedayID, completed: $0.completedAt != nil, today: PlannerLogic.dayKey(.now)) == group
        }
    }
    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let list = TaskList(name: name, sortOrder: lists.count)
        do { context.insert(list); try Mutations.save(context); listID = list.id; newListName = "" }
        catch { context.rollback(); self.error = error.localizedDescription }
    }

}

struct ListsView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var name = ""
    @State private var error: String?
    @State private var pendingDelete: TaskList?
    private var editable: [TaskList] { lists.filter { $0.id != TodayRules.somedayID } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Someday is built in: always first, never renamed or deleted.
                    Label("Someday", systemImage: "moon.zzz").foregroundStyle(.secondary)
                    ForEach(editable) { list in
                        HStack {
                            ListNameRow(list: list)
                            Menu {
                                Button("Move up") { shift(list, by: -1) }.disabled(editable.first?.id == list.id)
                                Button("Move down") { shift(list, by: 1) }.disabled(editable.last?.id == list.id)
                            } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 18)).frame(width: 44, height: 44) }
                                .accessibilityLabel("Reorder " + list.name)
                        }
                    }
                        .onMove(perform: moveLists)
                        .onDelete { indices in pendingDelete = indices.first.map { editable[$0] } }
                } header: { Text("Lists") }
                Section {
                    TextField("New list name", text: $name).accessibilityIdentifier("new-list-name")
                    Button("Add List") {
                        context.insert(TaskList(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: lists.count))
                        do { try Mutations.save(context); name = "" } catch { context.rollback(); self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.tint(accent.fill).navigationTitle("Edit Lists")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .modifier(MutationErrorModifier(error: $error))
                .confirmationDialog("Delete this list? Its tasks will move to Inbox.", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                    Button("Delete list", role: .destructive) {
                        guard let list = pendingDelete else { return }
                        do {
                            let id = list.id
                            let tasks = try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.listID == id }))
                            for task in tasks { task.listID = nil; task.updatedAt = .now }
                            context.delete(list); try Mutations.save(context); pendingDelete = nil
                        } catch { context.rollback(); self.error = error.localizedDescription }
                    }
                }
        }
    }
    private func shift(_ list: TaskList, by delta: Int) {
        guard let index = editable.firstIndex(where: { $0.id == list.id }) else { return }
        let next = index + delta
        guard editable.indices.contains(next) else { return }
        moveLists(from: IndexSet(integer: index), to: delta > 0 ? next + 1 : next)
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
    @State private var error: String?
    var body: some View {
        HStack {
            Circle().fill(DayTheme.color(list.color)).frame(width: 10, height: 10)
            TextField("List name", text: $name).onSubmit(saveName)
            if name != list.name {
                Button(action: saveName) { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Save list name")
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
