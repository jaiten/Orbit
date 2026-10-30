import SwiftUI
import SwiftData
import UIKit
import PhotosUI

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
        lists.filter(\.isNoteSection).map { NoteSection(id: $0.id.uuidString, name: $0.name, color: $0.color, listID: $0.id) }
            + [NoteSection(id: "none", name: "All notes", color: "clay", listID: nil)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                    PageHeader(eyebrow: "", title: "Notes")
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
                            section.listID == nil ? true : note.listID == section.listID
                        }
                        // Your own sections always show, so a new one has somewhere to start.
                        if !pages.isEmpty || (section.listID != nil && section.listID != TodayRules.somedayID && search.isEmpty) {
                            sectionView(section.id, name: section.name, color: section.color, listID: section.listID, pages: pages)
                        }
                    }
                    Button { managing = true } label: {
                        Label("Manage sections", systemImage: "folder.badge.gearshape")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("edit-sections")
                }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // The same bottom bar as Today; what you type here becomes a note.
            .captureDock(scheme) { Button { withAnimation(.orbit) { path.append(.new(section: nil, token: UUID())) } } label: { Label("Write a note", systemImage: "square.and.pencil").frame(maxWidth: .infinity, minHeight: 48) }.orbitSurface(radius: CGFloat(DesignTokens.radiusInput)) }
            .background(DayTheme.canvas(scheme)).tint(accent.fill)
            .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NoteRoute.self) { route in
                switch route {
                case .open(let id): NoteEditor(note: items.first { $0.id == id })
                case .new(let section, _): NoteEditor(note: nil, sectionID: section)
                }
            }
            .sheet(isPresented: $managing) { ListsView().presentationDragIndicator(.visible) }
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
                Button { if listID == nil { managing = true } else { withAnimation(.orbit) { path.append(.new(section: listID, token: UUID())) } } } label: {
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
                            // The row opens the page; ⋯ (or touch and hold) shows Copy text, Move, Make It a Task, Delete.
                            HStack(spacing: 0) {
                                NoteRow(note: note)
                                    .contentShape(Rectangle())
                                    .onTapGesture { withAnimation(.orbit) { path.append(.open(note.id)) } }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel(note.title.isEmpty ? (note.notes.isEmpty ? "Photo note" : NoteRules.snippet(note.notes)) : note.title)
                                    .accessibilityValue(NoteRules.snippet(note.notes))
                                    .accessibilityIdentifier("note-row")
                                    .accessibilityAction { withAnimation(.orbit) { path.append(.open(note.id)) } }
                                NoteMenu(note: note)
                            }
                            .contentShape(Rectangle())
                            .modifier(NoteActions(note: note))
                        }
                    }.orbitSurface(radius: CGFloat(DesignTokens.radiusCard))
                        .clipShape(RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusCard), style: .continuous))
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
            Image(systemName: NoteIcons.symbol(note.noteIcon)).font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? (note.notes.isEmpty ? "Photo note" : NoteRules.snippet(note.notes)) : note.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                let snippet = NoteRules.snippet(note.notes)
                if !snippet.isEmpty && !note.title.isEmpty { Text(snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
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
/// The note actions, shared by touch and hold and the row's ⋯ button.
struct NoteMenuItems: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    let note: PlannerTask
    @Binding var error: String?
    var body: some View {
        Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = NoteActions.text(of: note) }
        Menu("Move to section", systemImage: "folder") {
            Button("No section") { move(nil) }
            ForEach(lists.filter(\.isNoteSection)) { list in Button(list.name) { move(list.id) } }
            Button("Someday") { move(TodayRules.somedayID) }
        }
        Button("Make It a Task", systemImage: "checklist") { change { note.isNote = nil; if note.title.isEmpty { note.title = NoteRules.split(note.notes).title.isEmpty ? "Photo note" : NoteRules.split(note.notes).title }; note.updatedAt = .now; try Mutations.save(context) } }
        Button("Delete", systemImage: "trash", role: .destructive) { change { context.delete(note); try Mutations.save(context) } }
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

/// The row's ⋯ button.
struct NoteMenu: View {
    let note: PlannerTask
    @State private var error: String?
    var body: some View {
        Menu { NoteMenuItems(note: note, error: $error) } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("More for " + (note.title.isEmpty ? "Untitled" : note.title))
        .modifier(MutationErrorModifier(error: $error))
    }
}

/// Touch and hold a note: copy it, move it to another section, turn it into a task, or delete it.
struct NoteActions: ViewModifier {
    @Environment(\.modelContext) private var context
    @GestureState private var drag: CGFloat = 0
    @State private var revealingDelete = false
    let note: PlannerTask
    @State private var error: String?
    func body(content: Content) -> some View {
        content
            .offset(x: revealingDelete ? -76 : max(-76, min(0, drag)))
            .background(alignment: .trailing) {
                if revealingDelete || drag < -15 {
                    Button(role: .destructive) {
                        do { context.delete(note); try Mutations.save(context) }
                        catch { context.rollback(); self.error = error.localizedDescription }
                    } label: { Image(systemName: "trash").frame(width: 76).frame(maxHeight: .infinity).foregroundStyle(.white).background(Color.red) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete note")
                }
            }
            .clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 25)
                .updating($drag) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                }
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        withAnimation(.easeOut(duration: 0.18)) { revealingDelete = value.translation.width < -40 }
                    }
                })
            .contextMenu { NoteMenuItems(note: note, error: $error) }
            .modifier(MutationErrorModifier(error: $error))
    }
    static func text(of note: PlannerTask) -> String {
        [note.title, note.notes].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

private struct NoteIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.orbitAccent) private var accent
    @Binding var selection: String
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                    ForEach(NoteIcons.choices) { choice in
                        Button {
                            selection = choice.symbol; dismiss()
                        } label: {
                            Image(systemName: choice.symbol).font(.system(size: 24))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(selection == choice.symbol ? accent.fill.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).foregroundStyle(accent.text)
                            .accessibilityLabel(choice.name).accessibilityIdentifier("note-icon-" + choice.symbol)
                            .accessibilityAddTraits(selection == choice.symbol ? .isSelected : [])
                    }
                }.padding(20)
            }.navigationTitle("Note icon").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
    @State private var displayedEdited: Date?
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var icon = NoteIcons.defaultSymbol
    @State private var choosingIcon = false
    @State private var photos: [NotePhoto] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var focus: Field?
    private enum Field { case title, body }

    private var sectionName: String {
        if section == TodayRules.somedayID { return "Someday" }
        return lists.first { $0.id == section }?.name ?? "All"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { focus = nil; choosingIcon = true } label: {
                    Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(accent.fill)
                        .frame(width: 48, height: 48)
                }.buttonStyle(.plain).padding(.top, 8).accessibilityLabel("Change note icon")
                    .accessibilityValue(NoteIcons.name(icon))
                CaptureTextField(text: $title, focused: Binding(get: { focus == .title }, set: { editing in
                    if editing { focus = .title } else if focus == .title { focus = nil }
                }), identifier: "note-title", placeholder: "Untitled", minimumHeight: 56, maximumLines: 6,
                   onPasteImage: addPhoto, textStyle: .largeTitle, bold: true) { focus = .body }
                VStack(alignment: .leading, spacing: 2) {
                    property("Section", icon: "folder") {
                        Menu {
                            Picker("Section", selection: $section) {
                                Text("All").tag(nil as UUID?)
                                ForEach(lists.filter(\.isNoteSection)) { Text($0.name).tag(Optional($0.id)) }
                                Text("Someday").tag(Optional(TodayRules.somedayID))
                            }
                        } label: { Text(sectionName).foregroundStyle(.primary) }
                    }
                    if let note {
                        property("Edited", icon: "clock") {
                            Text((displayedEdited ?? note.updatedAt).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }
                }.font(.subheadline)
                Divider().padding(.vertical, 4)
                CaptureTextField(text: $text, focused: Binding(get: { focus == .body }, set: { editing in
                    if editing { focus = .body } else if focus == .body { focus = nil }
                }), identifier: "note-body", placeholder: "Start writing…", minimumHeight: 240, maximumLines: 24,
                   allowsNewlines: true, onPasteImage: addPhoto, textStyle: .body) {}
                ForEach(photos) { photo in
                    NotePhotoView(photo: photo) {
                        photos.removeAll { $0.id == photo.id }; save()
                    }
                }

            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DayTheme.canvas(scheme).ignoresSafeArea()).tint(accent.fill)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                defer { selectedPhoto = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    addPhoto(image)
                } catch { self.error = error.localizedDescription }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { PhotosPicker(selection: $selectedPhoto, matching: .images) { Image(systemName: "photo.badge.plus") }.accessibilityLabel("Add photo") }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = [title, text].filter { !$0.isEmpty }.joined(separator: "\n\n") }
                    if note != nil {
                        Button("Make It a Task", systemImage: "checklist") { makeTask() }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Note options")
            }
        }
        .onAppear(perform: load)
        .onDisappear { save() }
        .onChange(of: phase) { _, value in if value != .active { save() } }
        .onChange(of: section) { _, _ in if loaded { save() } }
        .onChange(of: icon) { _, _ in if loaded { save() } }
        .sheet(isPresented: $choosingIcon) {
            NoteIconPicker(selection: $icon).presentationDetents([.height(380), .medium]).presentationDragIndicator(.visible)
        }
        .onChange(of: text) { old, new in if loaded { photos = NotePhotos.reanchor(photos, from: old, to: new) } }
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
        if let note { displayedEdited = note.updatedAt; title = note.title; text = note.notes; section = note.listID; photos = note.photos; icon = NoteIcons.symbol(note.noteIcon) }
        else { section = sectionID; Task { try? await Task.sleep(for: .milliseconds(250)); focus = .title } }
        loaded = true
    }

    /// Creates the page on first content; afterwards writes only real changes.
    private func save() {
        guard loaded else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedIcon = icon == NoteIcons.defaultSymbol ? nil : icon
        do {
            if let note {
                let newTitle = trimmedTitle
                guard note.title != newTitle || note.notes != text || note.listID != section || note.photos != photos || note.noteIcon != savedIcon else { return }
                if section == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
                note.title = newTitle; note.notes = text; note.listID = section; note.photos = photos; note.noteIcon = savedIcon; note.updatedAt = .now
                try Mutations.save(context)
            } else if !trimmedTitle.isEmpty || !trimmedText.isEmpty || !photos.isEmpty {
                let created = PlannerTask(title: trimmedTitle, listID: section)
                created.isNote = true; created.notes = text; created.photos = photos; created.noteIcon = savedIcon
                if section == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
                context.insert(created)
                try Mutations.save(context)
                note = created
                if displayedEdited == nil { displayedEdited = created.updatedAt }
            }
        } catch { context.rollback(); self.error = error.localizedDescription }
    }

    private func addPhoto(_ image: UIImage) {
        guard photos.count < 12 else { error = "A note can hold up to 12 photos."; return }
        do { photos.append(try NotePhotos.save(image)); save() }
        catch { self.error = error.localizedDescription }
    }

    private func makeTask() {
        save()
        guard let note else { return }
        do { note.isNote = nil; if note.title.isEmpty { note.title = NoteRules.split(note.notes).title.isEmpty ? "Photo note" : NoteRules.split(note.notes).title }; note.updatedAt = .now; try Mutations.save(context); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

private struct NotePhotoView: View {
    let photo: NotePhoto
    let remove: () -> Void
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 500).clipShape(RoundedRectangle(cornerRadius: 10))
                    .contextMenu {
                        Button("Copy photo", systemImage: "doc.on.doc") { UIPasteboard.general.image = image }
                        Button("Remove photo", systemImage: "trash", role: .destructive, action: remove)
                    }
                    .overlay(alignment: .topTrailing) { Button(role: .destructive, action: remove) { Image(systemName: "trash").padding(12).background(.regularMaterial, in: Circle()) }.accessibilityLabel("Remove photo").padding(8) }
            } else {
                Button { Task { await load() } } label: { Label(failed ? "Photo unavailable — tap to retry" : "Loading photo…", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 100) }
            }
        }.task(id: photo.id) { await load() }
    }
    private func load() async {
        do { image = try await SyncService.shared.loadPhoto(photo.id); failed = false }
        catch { failed = true }
    }
}
