import SwiftUI
import SwiftData

/// Sync keeps both versions when two devices change the same thing; choose the one to keep.
struct ConflictReviewView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @ObservedObject private var sync = SyncService.shared
    @Query private var entries: [SyncEntry]
    @State private var message: String?
    private var conflicts: [SyncEntry] { entries.filter { $0.conflict != nil } }
    var body: some View {
        List {
            if conflicts.isEmpty { ContentUnavailableView("Nothing to Review", systemImage: "checkmark.circle") }
            ForEach(conflicts) { entry in
                Section {
                    version("On this iPhone", summary: SyncMerge.summary((try? SyncRecords.object(entry.payload)) ?? [:], deleted: entry.tombstone)) { resolve(entry, local: true) }
                    let record = (try? SyncRecords.object(entry.conflict ?? "{}")) ?? [:]
                    version("From sync", summary: SyncMerge.summary(record["payload"] as? [String: Any] ?? [:], deleted: record["deleted"] as? Bool ?? false)) { resolve(entry, local: false) }
                }
            }
        }.tint(accent.fill).navigationTitle("Review").navigationBarTitleDisplayMode(.inline)
            .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
    private func version(_ title: String, summary: String, keep: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(summary)
            Button("Keep This Version", action: keep)
        }.padding(.vertical, 4)
    }
    private func resolve(_ entry: SyncEntry, local: Bool) {
        Task { do { try await sync.resolve(entry, local: local, context: context) } catch { message = error.localizedDescription } }
    }
}
