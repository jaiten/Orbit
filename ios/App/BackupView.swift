import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var export = false
    @State private var importing = false
    @State private var document = BackupDocument()
    @State private var pending: [[String: Any]]?
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        List {
            Section {
                Button("Export planner", systemImage: "square.and.arrow.up") {
                    do { document = BackupDocument(data: try PlannerBackup.encode(SyncRecords.snapshots(context))); export = true } catch { self.error = error.localizedDescription }
                }
                Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
            } footer: { Text("Backups contain your planner text and habit history, without passwords or account tokens. Import replaces matching items and keeps other items. Imported changes sync to your account.") }
        }.navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $export, document: document, contentType: .json, defaultFilename: "Orbit-" + PlannerLogic.dayKey(.now)) { result in if case .failure(let failure) = result { error = failure.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pending = try PlannerBackup.decode(Data(contentsOf: url))
                } catch { self.error = "This backup could not be read. Your planner hasn’t changed. " + error.localizedDescription }
            }
            .confirmationDialog("Import \(pending?.count ?? 0) items?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Import and merge") { restore() }
            } message: { Text("Matching items will be replaced. Other items stay. You can Undo immediately after importing.") }
            .modifier(MutationErrorModifier(error: $error))
    }
    private func restore() {
        guard let pending else { return }
        do {
            for record in pending {
                var payload = record["payload"] as! [String: Any]; payload["updatedAt"] = Date.now.timeIntervalSince1970 * 1000
                try SyncRecords.apply(["key": record["key"]!, "payload": payload, "deleted": false], context: context)
            }
            try Mutations.save(context); Task { try? await refreshReminders(context) }; self.pending = nil
        } catch { context.rollback(); self.pending = nil; self.error = error.localizedDescription }
    }
}
