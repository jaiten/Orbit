import SwiftUI
import SwiftData
import UIKit

/// Where a note opens: an existing page, or a fresh one in a section. `token` makes each new page distinct.
enum NoteRoute: Hashable {
    case open(UUID)
    case new(section: UUID?, token: UUID)
}

/// Notes: titled pages of text, grouped into sections (Personal, Work, Someday…). Long text typed into
/// Add a task lands here too. Notes are task records marked `isNote`, so they sync, back up and undo
/// like everything else, but never appear as to-dos.
struct NotesView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \PlannerTask.updatedAt, order: .reverse) private var items: [PlannerTask]
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var search = ""
    @State private var path: [NoteRoute] = []
    @State private var managing = false
    @AppStorage("collapsedNoteSections") private var collapsedStorage = ""
    private var collapsed: Set<String> { Set(collapsedStorage.split(separator: ",").map(String.init)) }
    private var notes: [PlannerTask] {
        items.filter { item in
            item.note && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.notes.localizedCaseInsensitiveContains(search))
        }
    }
    /// Your sections in order, then notes without one, then Someday.
    private struct NoteSection: Identifiable { let id: String; let name: String; let color: String; let listID: UUID? }
    private var sections: [NoteSection] {
        lists.filter { $0.id != TodayRules.somedayID }.map { NoteSection(id: $0.id.uuidString, name: $0.name, color: $0.color, listID: $0.id) }
            + [NoteSection(id: "none", name: "Unsorted", color: "clay", listID: nil),
               NoteSection(id: TodayRules.somedayID.uuidString, name: "Someday", color: "lavender", listID: TodayRules.somedayID)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                    PageHeader(eyebrow: "Write it down", title: "Notes", subtitle: "Ideas, lists and anything longer than a task.") {
                        Button { managing = true } label: { Text("Sections").padding(.horizontal, 14).frame(minHeight: 44) }
                            .accessibilityIdentifier("edit-sections")
                        Button { path.append(.new(section: nil, token: UUID())) } label: {
                            Image(systemName: "square.and.pencil").font(.system(size: 19)).frame(width: 44, height: 44)
                        }.accessibilityLabel("New note")
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search notes", text: $search).textInputAutocapitalization(.never)
                    }.padding(.horizontal, 14).frame(minHeight: 44).orbitSurface(radius: CGFloat(DesignTokens.radiusInput))
                    if items.filter(\.note).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No notes yet").font(.headline)
                            Text("Tap the pencil to start a page. Anything long you type into Add a task becomes a note too.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.orbitCard()
                    }
                    ForEach(sections) { section in
                        let pages = notes.filter { note in
                            section.listID == nil ? (note.listID == nil || (note.listID != TodayRules.somedayID && !lists.contains { $0.id == note.listID })) : note.listID == section.listID
                        }
                        // Your own sections always show, so a new one has somewhere to start.
                        if !pages.isEmpty || (section.listID != nil && section.listID != TodayRules.somedayID && search.isEmpty) {
                            sectionView(section.id, name: section.name, color: section.color, listID: section.listID, pages: pages)
                        }
                    }
                }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DayTheme.canvas(scheme)).tint(accent.fill)
            .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NoteRoute.self) { route in
                switch route {
                case .open(let id): NoteEditor(note: items.first { $0.id == id })
                case .new(let section, _): NoteEditor(note: nil, sectionID: section)
                }
            }
            .sheet(isPresented: $managing) { ListsView() }
        }
    }

    /// A Notion-style toggle: chevron, coloured dot, name and count; pages sit in one quiet card below.
    private func sectionView(_ id: String, name: String, color: String, listID: UUID?, pages: [PlannerTask]) -> some View {
        let open = !collapsed.contains(id) || !search.isEmpty
        return VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
            HStack(spacing: 8) {
                Button { toggle(id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Circle().fill(DayTheme.color(color)).frame(width: 8, height: 8)
                        Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text("\(pages.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(name), \(pages.count) notes").accessibilityValue(open ? "Expanded" : "Collapsed")
                Button { path.append(.new(section: listID, token: UUID())) } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                }.foregroundStyle(.secondary).accessibilityLabel("New note in \(name)")
            }.padding(.horizontal, 4)
            if open {
                if pages.isEmpty {
                    Text("No notes in \(name) yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, note in
                            if index > 0 { Divider().padding(.leading, 48) }
                            // A button rather than a NavigationLink, so touch and hold opens the menu, not the page.
                            Button { path.append(.open(note.id)) } label: { NoteRow(note: note) }
                                .buttonStyle(OrbitPress())
                                .accessibilityLabel(note.title.isEmpty ? "Untitled" : note.title)
                                .accessibilityValue(NoteRules.snippet(note.notes))
                                .accessibilityIdentifier("note-row")
                                .modifier(NoteActions(note: note))
                        }
                    }.orbitSurface(radius: CGFloat(DesignTokens.radiusCard))
                }
            }
        }
        .animation(.orbit, value: open)
    }

    private func toggle(_ id: String) {
        var values = collapsed
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        collapsedStorage = values.sorted().joined(separator: ",")
    }
}

/// A page in a section: icon, title, the start of the text and when it last changed.
struct NoteRow: View {
    let note: PlannerTask
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "Untitled" : note.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                let snippet = NoteRules.snippet(note.notes)
                if !snippet.isEmpty { Text(snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Text(note.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .accessibilityElement(children: .ignore).accessibilityHint("Opens the note")
    }
}

/// Touch and hold a note: copy it, move it to another section, turn it into a task, or delete it.
struct NoteActions: ViewModifier {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    let note: PlannerTask
    @State private var error: String?
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = NoteActions.text(of: note) }
            Menu("Move to section", systemImage: "folder") {
                Button("No section") { move(nil) }
                ForEach(lists.filter { $0.id != TodayRules.somedayID }) { list in Button(list.name) { move(list.id) } }
                Button("Someday") { move(TodayRules.somedayID) }
            }
            Button("Make It a Task", systemImage: "checklist") { change { note.isNote = nil; note.updatedAt = .now; try Mutations.save(context) } }
            Button("Delete", systemImage: "trash", role: .destructive) { change { context.delete(note); try Mutations.save(context) } }
        }.modifier(MutationErrorModifier(error: $error))
    }
    static func text(of note: PlannerTask) -> String {
        note.notes.isEmpty ? note.title : note.title + "\n\n" + note.notes
    }
    private func move(_ id: UUID?) {
        change {
            if id == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
            note.listID = id; note.updatedAt = .now; try Mutations.save(context)
        }
    }
    private func change(_ action: () throws -> Void) {
        do { try action() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

/// A note as a page: an icon, a large title, a few properties and the text below, like Notion.
/// Changes save shortly after typing pauses and when leaving the page. A new page is created only
/// once something is written.
struct NoteEditor: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State var note: PlannerTask?
    var sectionID: UUID? = nil
    @State private var title = ""
    @State private var text = ""
    @State private var section: UUID?
    @State private var loaded = false
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    private var sectionName: String {
        if section == TodayRules.somedayID { return "Someday" }
        return lists.first { $0.id == section }?.name ?? "No section"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "doc.text").font(.system(size: 34, weight: .light)).foregroundStyle(accent.fill)
                    .padding(.top, 8).accessibilityHidden(true)
                TextField("Untitled", text: $title, axis: .vertical)
                    .font(.largeTitle.bold()).tracking(-0.8)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .accessibilityIdentifier("note-title")
                VStack(alignment: .leading, spacing: 2) {
                    property("Section", icon: "folder") {
                        Menu {
                            Picker("Section", selection: $section) {
                                Text("No section").tag(nil as UUID?)
                                ForEach(lists.filter { $0.id != TodayRules.somedayID }) { Text($0.name).tag(Optional($0.id)) }
                                Text("Someday").tag(Optional(TodayRules.somedayID))
                            }
                        } label: { Text(sectionName).foregroundStyle(.primary) }
                    }
                    if let note {
                        property("Edited", icon: "clock") {
                            Text(note.updatedAt.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                        }
                    }
                }.font(.subheadline)
                Divider().padding(.vertical, 4)
                TextField("Start writing…", text: $text, axis: .vertical)
                    .font(.body).lineSpacing(5)
                    .focused($focus, equals: .body)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                    .accessibilityIdentifier("note-body")
            }
            .padding(.horizontal, 24).padding(.bottom, 80)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DayTheme.canvas(scheme)).tint(accent.fill)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = text.isEmpty ? title : title + "\n\n" + text }
                    if note != nil {
                        Button("Make It a Task", systemImage: "checklist") { makeTask() }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Note options")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil; save() }
            }
        }
        .onAppear(perform: load)
        .onDisappear { save() }
        .onChange(of: phase) { _, value in if value != .active { save() } }
        .onChange(of: section) { _, _ in if loaded { save() } }
        // Return in the title moves to the text, as in Notion.
        .onChange(of: title) { _, value in
            guard value.contains("\n") else { return }
            title = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            focus = .body
        }
        .task(id: title + "\u{1F}" + text) {
            // Save once typing pauses, so sync sends one change rather than one per key.
            guard loaded else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { save() }
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete note", role: .destructive) {
                guard let note else { return }
                do { context.delete(note); try Mutations.save(context); self.note = nil; title = ""; text = ""; dismiss() }
                catch { context.rollback(); self.error = error.localizedDescription }
            }
        }
        .modifier(MutationErrorModifier(error: $error))
    }

    private func property<Content: View>(_ name: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Label(name, systemImage: icon).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }.frame(minHeight: 36)
    }

    private func load() {
        guard !loaded else { return }
        if let note { title = note.title; text = note.notes; section = note.listID }
        else { section = sectionID; focus = .title }
        loaded = true
    }

    /// Creates the page on first content; afterwards writes only real changes.
    private func save() {
        guard loaded else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let note {
                let newTitle = trimmedTitle.isEmpty ? (trimmedText.isEmpty ? "Untitled" : NoteRules.split(trimmedText).title) : trimmedTitle
                guard note.title != newTitle || note.notes != text || note.listID != section else { return }
                if section == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
                note.title = newTitle; note.notes = text; note.listID = section; note.updatedAt = .now
                try Mutations.save(context)
            } else if !trimmedTitle.isEmpty || !trimmedText.isEmpty {
                let created = PlannerTask(title: trimmedTitle.isEmpty ? NoteRules.split(trimmedText).title : trimmedTitle, listID: section)
                created.isNote = true; created.notes = text
                if section == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
                context.insert(created)
                try Mutations.save(context)
                note = created
            }
        } catch { context.rollback(); self.error = error.localizedDescription }
    }

    private func makeTask() {
        save()
        guard let note else { return }
        do { note.isNote = nil; note.updatedAt = .now; try Mutations.save(context); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
