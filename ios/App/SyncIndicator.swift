import SwiftUI
import SwiftData

struct SyncIndicator: View {
    @ObservedObject private var sync = SyncService.shared
    @Environment(\.modelContext) private var context
    @State private var details = false
    var body: some View {
        Button { details = true } label: {
            Group {
                if sync.syncing { ProgressView().controlSize(.small) }
                else { Image(systemName: sync.status.contains("Saved locally") || sync.status.contains("review") ? "exclamationmark.icloud" : sync.email == nil ? "icloud" : "checkmark.icloud").font(.system(size: 17)) }
            }.frame(width: 44, height: 44).foregroundStyle(.secondary)
        }.accessibilityLabel("Sync status").sheet(isPresented: $details) {
            NavigationStack {
                Form {
                    Text(sync.status)
                    Text("Edits save on this device immediately. Connected devices receive changes while Orbit is open.").font(.footnote).foregroundStyle(.secondary)
                    Button("Sync now") { Task { await sync.run(context) } }.disabled(sync.email == nil || sync.syncing)
                }.navigationTitle("Sync").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { details = false } }
            }.presentationDetents([.medium])
        }
    }
}
