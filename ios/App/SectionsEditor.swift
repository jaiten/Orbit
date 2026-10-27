import SwiftUI
import SwiftData

/// Sections (stored as lists) group notes and tasks. Someday is built in.
struct ListsView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var name = ""
    @FocusState private var naming: Bool
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
                } header: { Text("Sections") }
                Section {
                    TextField("New section name", text: $name).focused($naming).accessibilityIdentifier("new-list-name")
                    Button("Add Section") {
                        context.insert(TaskList(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: lists.count))
                        do { try Mutations.save(context); name = "" } catch { context.rollback(); self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.onAppear { naming = true }.tint(accent.fill).navigationTitle("Edit Sections")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .modifier(MutationErrorModifier(error: $error))
                .confirmationDialog("Delete this section? Its notes and tasks are kept, without a section.", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                    Button("Delete section", role: .destructive) {
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
