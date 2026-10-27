import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Export everything as JSON (the same format as Windows), tasks as CSV, and import with a preview.
struct BackupView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @State private var exporting = false
    @State private var exportType = UTType.json
    @State private var exportName = ""
    @State private var importing = false
    @State private var document = ExportDocument()
    @State private var plan: PlannerBackup.Plan?
    @State private var photoFiles: [String: String] = [:]
    @State private var replaceChanged = false
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        List {
            Section {
                Button("Export Everything (JSON)", systemImage: "square.and.arrow.up") { export(csv: false) }
                Button("Export Tasks (CSV)", systemImage: "tablecells") { export(csv: true) }
                Button("Import…", systemImage: "square.and.arrow.down") { importing = true }
            } footer: { Text("The JSON file holds your tasks, lists and habit history and can be imported on iPhone or Windows. No account details are included.") }
            if let plan { ImportPreview(plan: plan, replaceChanged: $replaceChanged, confirm: restore, cancel: { self.plan = nil }) }
        }.tint(accent.fill).navigationTitle("Import & Export").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportName) { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    photoFiles = ((try JSONSerialization.jsonObject(with: data)) as? [String: Any])?["photoFiles"] as? [String: String] ?? [:]
                    plan = PlannerBackup.plan(current: try SyncRecords.snapshots(context), records: try PlannerBackup.decode(Data(contentsOf: url)))
                    replaceChanged = false
                } catch { self.error = "This file could not be read. Nothing has changed. " + error.localizedDescription }
            }
            .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .modifier(MutationErrorModifier(error: $error))
    }
    private func export(csv: Bool) {
        Task {
        do {
            if !csv {
                for task in try context.fetch(FetchDescriptor<PlannerTask>()) { for photo in task.photos { _ = try await SyncService.shared.loadPhoto(photo.id) } }
            }
            let snapshots = try SyncRecords.snapshots(context)
            if csv {
                let records = try snapshots.map { ["key": $0.key, "payload": try SyncRecords.object($0.value)] as [String: Any] }
                // The byte-order mark lets Excel read accented characters correctly.
                document = ExportDocument(data: Data(("\u{FEFF}" + PlannerBackup.tasksCSV(records)).utf8))
                exportType = .commaSeparatedText; exportName = "Orbit-tasks-" + PlannerLogic.dayKey(.now)
            } else {
                document = ExportDocument(data: try PlannerBackup.encode(snapshots))
                exportType = .json; exportName = "Orbit-" + PlannerLogic.dayKey(.now)
            }
            exporting = true
        } catch { self.error = error.localizedDescription }
        }
    }
    private func restore() {
        guard let plan else { return }
        let chosen = plan.added + (replaceChanged ? plan.changed : [])
        do {
            try NotePhotos.restoreFiles(photoFiles, records: chosen)
            for record in chosen {
                var payload = record["payload"] as! [String: Any]; payload["updatedAt"] = Date.now.timeIntervalSince1970 * 1000
                try SyncRecords.apply(["key": record["key"]!, "payload": payload, "deleted": false], context: context)
            }
            try Mutations.save(context, undoKind: .imported); Task { try? await refreshReminders(context) }
            self.plan = nil
            message = chosen.isEmpty ? "Nothing new to import." : "Imported \(chosen.count) \(chosen.count == 1 ? "item" : "items"). You can Undo right away."
        } catch { context.rollback(); self.plan = nil; self.error = error.localizedDescription }
    }
}

/// What an import will do, before anything changes. Items that differ need an explicit choice.
private struct ImportPreview: View {
    let plan: PlannerBackup.Plan
    @Binding var replaceChanged: Bool
    var confirm: () -> Void
    var cancel: () -> Void
    var body: some View {
        Section {
            LabeledContent("New items", value: "\(plan.added.count)")
            LabeledContent("Already here", value: "\(plan.same.count)")
            if !plan.changed.isEmpty {
                LabeledContent("Different from yours", value: "\(plan.changed.count)")
                ForEach(Array(plan.changed.enumerated()), id: \.offset) { _, record in Text(PlannerBackup.title(record)).foregroundStyle(.secondary) }
                Toggle("Replace with the imported versions", isOn: $replaceChanged)
            }
            Button("Import", action: confirm)
            Button("Cancel", role: .cancel, action: cancel)
        } header: { Text("Import preview") } footer: { Text("New items are added. Items that differ stay as they are unless you choose to replace them.") }
    }
}
