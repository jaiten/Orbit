import SwiftUI
import SwiftData

struct TasksView: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.modelContext) private var context
    @State private var error: String?
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var search = ""
    @State private var listID: UUID?
    @State private var showCompleted = false
    @State private var adding = false
    @State private var editing: PlannerTask?
    @State private var manageLists = false
    private var filtered: [PlannerTask] {
        tasks.filter { task in
            (listID == nil || task.listID == listID) && (showCompleted || task.completedAt == nil) &&
            (search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.tags.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    AccentPicker(title: "List", selection: $listID, choices: [(nil as UUID?, "All Tasks"), (Optional(TodayRules.somedayID), "Someday")] + lists.filter { $0.id != TodayRules.somedayID }.map { (Optional($0.id), $0.name) })
                    Toggle("Show completed", isOn: $showCompleted)
                }
                Section {
                    if filtered.isEmpty { ContentUnavailableView(listID == TodayRules.somedayID ? "Nothing for Someday" : "No Tasks", systemImage: "checklist") }
                    ForEach(filtered) { task in
                        TaskRow(task: task) { editing = task }.listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                if task.completedAt == nil && !TodayRules.onDay(TodayRules.item(task), day: PlannerLogic.dayKey(.now), today: PlannerLogic.dayKey(.now)) {
                                    Button("Add to Today", systemImage: "sun.max") { change { TodayRules.moveToDay(task, day: .now) } }.tint(DayTheme.accentColor(accentTheme))
                                }
                            }
                    }
                }
            }.tint(DayTheme.accentColor(accentTheme)).searchable(text: $search, prompt: "Search tasks or tags").navigationTitle("Lists")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Edit Lists") { manageLists = true } }
                    ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("New task") }
                }
                .sheet(isPresented: $adding) { QuickCapture() }.sheet(item: $editing) { TaskEditor(task: $0) }
                .sheet(isPresented: $manageLists) { ListsView() }
                .modifier(MutationErrorModifier(error: $error))
        }
    }
}

extension TasksView {
    private func change(_ action: () throws -> Void) {
        do { try action(); try Mutations.save(context); Task { try? await refreshReminders(context) } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct ListsView: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
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
                    ForEach(editable) { list in ListNameRow(list: list) }
                        .onDelete { indices in pendingDelete = indices.first.map { editable[$0] } }
                } header: { Text("Lists") }
                Section {
                    TextField("New list name", text: $name)
                    Button("Add List") {
                        context.insert(TaskList(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: lists.count))
                        do { try Mutations.save(context); name = "" } catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.tint(DayTheme.accentColor(accentTheme)).navigationTitle("Lists").toolbar { Button("Done") { dismiss() } }
                .modifier(MutationErrorModifier(error: $error))
                .confirmationDialog("Delete this list? Its tasks will move to Inbox.", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                    Button("Delete list", role: .destructive) {
                        guard let list = pendingDelete else { return }
                        do {
                            let id = list.id
                            let tasks = try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.listID == id }))
                            for task in tasks { task.listID = nil; task.updatedAt = .now }
                            context.delete(list); try Mutations.save(context); pendingDelete = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
}

struct ListNameRow: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
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
