import SwiftUI
import SwiftData

/// Account: sync status, sign-in, email confirmation, devices and sign-out.
struct AccountView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @ObservedObject private var sync = SyncService.shared
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Text(sync.status)
                Text("Edits save on this device first. Connected devices receive changes while Orbit is open.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Sync") }
            if let account = sync.email {
                Section("Signed in") {
                    Text(account)
                    NavigationLink("Change Password") { PasswordChangeView() }
                    NavigationLink("Devices") { DevicesView() }
                    Button("Sync Now") { Task { await sync.run(context) } }.disabled(sync.syncing)
                    Button("Sign Out", role: .destructive) { Task { do { try await sync.signOut() } catch { message = error.localizedDescription } } }
                }
            } else {
                SignInSection(message: $message)
            }
        }.tint(accent.fill).navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
}

private struct SignInSection: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var sync = SyncService.shared
    @Binding var message: String?
    @State private var email = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var confirmationCode = ""
    @State private var resendAfter = Date.distantPast
    var body: some View {
        Section {
            TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $password).textContentType(.password)
            Button("Sign in") { authenticate(create: false) }.disabled(signingIn || email.isEmpty || password.isEmpty)
            Button("Forgot password?") {
                signingIn = true
                Task { defer { signingIn = false }; do { try await sync.requestRecovery(email: email); message = "If this account exists, a recovery email is on its way. Open its newest link on this same device." } catch { message = error.localizedDescription } }
            }.disabled(signingIn || email.isEmpty)
            Button("Create account") { authenticate(create: true) }.disabled(signingIn || email.isEmpty || password.count < 8)
            DisclosureGroup("Email confirmation") {
                Text("Open the newest confirmation email and tap its link, then sign in above. If you have a confirmation code, you can enter it below.").font(.footnote).foregroundStyle(.secondary)
                TextField("Confirmation code (if provided)", text: $confirmationCode)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad)
                Button("Confirm account") { confirmAccount() }
                    .disabled(signingIn || email.isEmpty || confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Button(timeline.date < resendAfter ? "Resend available shortly" : "Resend confirmation email") { resendCode() }
                        .disabled(signingIn || email.isEmpty || timeline.date < resendAfter)
                }
                Text("Enter the newest code from your email. Expired links cannot be reused.").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Use the same account on your PC. Everything stays available offline.").font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Sign In") }
    }
    private func authenticate(create: Bool) {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { message = try await sync.signIn(email: email, password: password, create: create, context: context); password = "" }
            catch { message = error.localizedDescription }
        }
    }
    private func confirmAccount() {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { try await sync.confirm(email: email, code: confirmationCode, context: context); confirmationCode = ""; password = "" }
            catch { message = error.localizedDescription }
        }
    }
    private func resendCode() {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { try await sync.resendConfirmation(email: email); resendAfter = .now.addingTimeInterval(60); message = "If this account needs confirmation, a fresh confirmation email is on its way." }
            catch { message = error.localizedDescription }
        }
    }
}
