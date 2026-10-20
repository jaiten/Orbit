import SwiftUI

struct PasswordChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sync = SyncService.shared
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text(sync.email ?? "Your Orbit account").foregroundStyle(.secondary)
                SecureField("New password", text: $password).textContentType(.newPassword)
                SecureField("Repeat password", text: $confirmation).textContentType(.newPassword)
                Button(busy ? "Saving…" : "Save password") {
                    busy = true
                    Task { defer { busy = false }; do { try await sync.changePassword(password); password = ""; confirmation = ""; dismiss() } catch { self.error = error.localizedDescription } }
                }.disabled(busy || password.count < 8 || password != confirmation)
            } footer: { Text("Use at least 8 characters. After recovering your account, review Devices & active sign-ins and remove anything you don’t recognize.") }
        }.navigationTitle("Set a new password").navigationBarTitleDisplayMode(.inline).modifier(MutationErrorModifier(error: $error))
    }
}
