import SwiftUI

struct ConnectedDevice: Identifiable {
    let id: String
    let name: String
    let current: Bool
    let seen: String
    var lastSeen: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: seen) ?? ISO8601DateFormatter().date(from: seen)
    }
}

struct DevicesView: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @State private var devices: [ConnectedDevice] = []
    @State private var loading = true
    @State private var error: String?
    @State private var removing: ConnectedDevice?
    var body: some View {
        List {
            Section {
                if loading { ProgressView("Checking sign-ins") }
                ForEach(devices) { device in
                    HStack {
                        Image(systemName: device.name.contains("Windows") ? "desktopcomputer" : "iphone").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                            if device.current { Text("This device").font(.caption).foregroundStyle(.secondary) }
                            if let date = device.lastSeen { (Text("Last active ") + Text(date, style: .relative)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if !device.current { Button("Remove", role: .destructive) { removing = device }.font(.caption) }
                    }.padding(.vertical, 4)
                }
            } header: { Text("\(devices.count) active sign-ins") } footer: {
                Text("A device can have multiple sign-ins. Removing one immediately blocks that sign-in from Orbit sync. Downloaded data stays on that device. To regain access, it must sign in again.")
            }
        }.tint(DayTheme.accentColor(accentTheme)).navigationTitle("Devices").navigationBarTitleDisplayMode(.inline)
            .task { await reload() }.refreshable { await reload() }
            .confirmationDialog("Remove this device’s sync access?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove access", role: .destructive) { if let device = removing { Task { do { try await SyncService.shared.removeDevice(device.id); await reload() } catch { self.error = error.localizedDescription } } }; removing = nil }
            }.modifier(MutationErrorModifier(error: $error))
    }
    private func reload() async {
        loading = true; defer { loading = false }
        do { devices = try await SyncService.shared.devices() } catch { self.error = error.localizedDescription }
    }
}
