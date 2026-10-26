import Foundation
import SwiftData
import SwiftUI
import Security
import WidgetKit
import UIKit
import OSLog

@MainActor final class SyncService: ObservableObject {
    static let shared = SyncService()
    @Published var status = "Saved on this device"
    @Published var email: String?
    @Published var recoveryReady = false
    private let base = "https://uwcwnjwijvawvvffaxdr.supabase.co"
    private let key = "sb_publishable_m0nf1UT5Q2vLryIVocVbXA_-q5tDD53"
    private var session: [String: Any]?
    private var busy = false
    private var again = false
    private var lastDeviceCheck = Date.distantPast
    @Published var syncing = false
    private let realtime = RealtimeWakeup()
    private var realtimeAllowed = true
    private let logger = Logger(subsystem: "com.jaiten.orbit", category: "sync")
    private init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "OrbitSession", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data { session = try? JSONSerialization.jsonObject(with: data) as? [String: Any]; email = (session?["user"] as? [String: Any])?["email"] as? String }
    }
    private func saveSession(_ value: [String: Any]?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "OrbitSession"]
        var value = value
        if value != nil, value?["expires_at"] == nil, let seconds = value?["expires_in"] as? Double {
            value?["expires_at"] = Date.now.timeIntervalSince1970 + seconds
        }
        if let value {
            let data = try JSONSerialization.data(withJSONObject: value)
            let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if result == errSecItemNotFound { result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
            guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        } else { SecItemDelete(query as CFDictionary) }
        session = value; email = (value?["user"] as? [String: Any])?["email"] as? String
    }
    private func request(_ path: String, body: [String: Any]? = nil, authenticated: Bool = true, method: String? = nil) async throws -> Any {
        var request = URLRequest(url: URL(string: base + path)!); request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "apikey")
        if authenticated, let token = session?["access_token"] as? String { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let method { request.httpMethod = method }
        let (data, response) = try await URLSession.shared.data(for: request)
        let value: Any = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = value as? [String: Any]; throw NSError(domain: "Orbit", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: error?["msg"] as? String ?? error?["message"] as? String ?? error?["error_description"] as? String ?? "Couldn’t reach sync. Your changes are saved locally."])
        }
        return value
    }
    func signIn(email: String, password: String, create: Bool, context: ModelContext) async throws -> String {
        guard !busy else { return "Sync is finishing. Please try again." }
        let path = create ? "/auth/v1/signup?redirect_to=orbit%3A%2F%2Fauth" : "/auth/v1/token?grant_type=password"
        guard let result = try await request(path, body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password], authenticated: false) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        guard result["access_token"] != nil else { return "Open the newest confirmation email, tap its link, then sign in here." }
        guard let user = result["user"] as? [String: Any], let id = user["id"] as? String else { throw CocoaError(.coderReadCorrupt) }
        try SyncRecords.bind(id, context: context); try saveSession(result); await run(context); return "Signed in"
    }
    func requestRecovery(email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let challenge = try RecoveryFlow.create(email: email)
        _ = try await request("/auth/v1/recover?redirect_to=orbit%3A%2F%2Fauth", body: ["email": email, "code_challenge": challenge, "code_challenge_method": "s256"], authenticated: false)
    }
    func acceptRecovery(code: String, context: ModelContext) async throws {
        let pending = try RecoveryFlow.pending()
        guard let result = try await request("/auth/v1/token?grant_type=pkce", body: ["auth_code": code, "code_verifier": pending.verifier], authenticated: false) as? [String: Any],
              result["access_token"] is String, let user = result["user"] as? [String: Any], let id = user["id"] as? String, let email = user["email"] as? String, email.lowercased() == pending.email else { throw CocoaError(.coderReadCorrupt) }
        try SyncRecords.bind(id, context: context); try saveSession(result); RecoveryFlow.clear(); recoveryReady = true
    }
    func changePassword(_ password: String) async throws {
        guard session != nil, password.count >= 8 else { throw CocoaError(.coderInvalidValue) }
        _ = try await request("/auth/v1/user", body: ["password": password], method: "PUT")
        recoveryReady = false
    }
    func resendConfirmation(email: String) async throws {
        _ = try await request("/auth/v1/resend?redirect_to=orbit%3A%2F%2Fauth", body: ["type": "signup", "email": email.trimmingCharacters(in: .whitespacesAndNewlines)], authenticated: false)
    }
    func confirm(email: String, code: String, context: ModelContext) async throws {
        guard !busy else { throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync is finishing. Please try again."]) }
        guard let result = try await request("/auth/v1/verify", body: ["type": "email", "email": email.trimmingCharacters(in: .whitespacesAndNewlines), "token": code.trimmingCharacters(in: .whitespacesAndNewlines)], authenticated: false) as? [String: Any],
              result["access_token"] != nil, let user = result["user"] as? [String: Any], let id = user["id"] as? String else { throw CocoaError(.coderReadCorrupt) }
        try SyncRecords.bind(id, context: context); try saveSession(result); await run(context)
    }
    func suspendRealtime() { realtimeAllowed = false; realtime.stop() }
    func resumeRealtime() { realtimeAllowed = true }
    func devices() async throws -> [ConnectedDevice] {
        guard let values = try await request("/rest/v1/rpc/orbit_devices_list", body: ["p_name": UIDevice.current.model]) as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        return values.compactMap { value in
            guard let id = value["id"] as? String, let name = value["name"] as? String else { return nil }
            return ConnectedDevice(id: id, name: name, current: value["current"] as? Bool ?? false, seen: value["last_seen"] as? String ?? "")
        }
    }
    func removeDevice(_ id: String) async throws {
        _ = try await request("/rest/v1/rpc/orbit_device_remove", body: ["p_session": id])
    }
    func signOut() async throws {
        guard !busy else { throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync is finishing. Please try again."]) }
        _ = try await request("/auth/v1/logout?scope=local", body: [:])
        realtime.stop(); try saveSession(nil); lastDeviceCheck = .distantPast; status = "Saved on this device"
    }
    func deleteAccount(context: ModelContext) async throws {
        guard !busy, session != nil else { throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync is finishing. Please try again."]) }
        busy = true; syncing = true; again = false
        realtime.stop()
        defer { busy = false; syncing = false }
        _ = try await request("/rest/v1/rpc/orbit_delete_account", body: [:])
        try saveSession(nil)
        try SyncRecords.erasePlanner(context)
        lastDeviceCheck = .distantPast
        status = "Account and synced data deleted"
        WidgetCenter.shared.reloadAllTimelines()
        try? await refreshReminders(context)
    }
    func run(_ context: ModelContext) async {
        if busy { again = true; return }
        guard session != nil else { return }
        busy = true; syncing = true; again = false
        let started = Date.now
        var uploaded = 0, pulled = 0
        defer {
            busy = false; syncing = false
            if again { Task { await self.run(context) } }
        }
        do {
            if let expires = session?["expires_at"] as? Double, expires < Date.now.timeIntervalSince1970 + 60, let token = session?["refresh_token"] as? String {
                guard let renewed = try await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": token], authenticated: false) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }; try saveSession(renewed)
            }
            guard let user = session?["user"] as? [String: Any], let uid = user["id"] as? String else { throw CocoaError(.coderReadCorrupt) }
            if Date.now.timeIntervalSince(lastDeviceCheck) > 60 { _ = try await devices(); lastDeviceCheck = .now }
            if realtimeAllowed { realtime.start(token: session?["access_token"] as? String ?? "", userID: uid) { [weak self] in
                Task { await self?.run(context) }
            } }
            try SyncRecords.bind(uid, context: context); try SyncRecords.capture(context); try context.save(); status = "Syncing…"
            for entry in try context.fetch(FetchDescriptor<SyncEntry>()) where entry.conflict != nil {
                try receive(try SyncRecords.object(entry.conflict!), context: context)
            }
            let pending = try context.fetch(FetchDescriptor<SyncEntry>()).filter { $0.dirty && $0.conflict == nil && $0.key != "owner" }
            for entry in pending {
                let mutation = entry.mutation
                let body: [String: Any] = ["p_key": entry.key, "p_payload": try SyncRecords.object(entry.payload), "p_deleted": entry.tombstone, "p_base": entry.revision, "p_mutation": mutation]
                guard let response = try await request("/rest/v1/rpc/orbit_put", body: body) as? [String: Any], let record = response["record"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
                if response["accepted"] as? Bool == true { entry.basePayload = try SyncRecords.json(record["payload"] ?? [:]); entry.revision = record["revision"] as? Int ?? entry.revision; if entry.mutation == mutation { entry.dirty = false; entry.conflict = nil }; try context.save() }
                else { try receive(record, context: context) }
                uploaded += 1
            }
            var offset = 0
            while true {
                guard let records = try await request("/rest/v1/orbit_records?select=*&order=key&limit=500&offset=\(offset)") as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
                for record in records { try receive(record, context: context) }
                pulled += records.count
                if records.count < 500 { break }; offset += 500
            }
            // Records from older devices may still contain repeating tasks.
            if try Migrations.run(context) > 0 { again = true }
            let entries = try context.fetch(FetchDescriptor<SyncEntry>())
            status = entries.contains { $0.conflict != nil } ? "Changes need review in Settings" : entries.contains { $0.dirty } ? "Changes waiting to sync" : "All changes synced"
            WidgetCenter.shared.reloadAllTimelines()
            try await refreshReminders(context)
            if entries.contains(where: { $0.dirty && $0.conflict == nil && $0.key != "owner" }) { again = true }
            logger.info("completed duration_ms=\(Int(Date.now.timeIntervalSince(started) * 1000), privacy: .public) uploaded=\(uploaded, privacy: .public) pulled=\(pulled, privacy: .public)")
        } catch {
            again = false; status = "Saved locally · " + error.localizedDescription
            let value = error as NSError
            logger.error("failed duration_ms=\(Int(Date.now.timeIntervalSince(started) * 1000), privacy: .public) domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
        }
    }
    private func receive(_ record: [String: Any], context: ModelContext) throws {
        guard let key = record["key"] as? String, let revision = record["revision"] as? Int, let payload = record["payload"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        let value = try SyncRecords.json(payload), deleted = record["deleted"] as? Bool ?? false
        let old = try context.fetch(FetchDescriptor<SyncEntry>()).first { $0.key == key }
        if let old, old.dirty {
            if revision > old.revision {
                let local = try SyncRecords.object(old.payload)
                let base = try old.basePayload.map { try SyncRecords.object($0) }
                if old.tombstone == deleted, let merged = SyncMerge.merge(local: local, remote: payload, base: base) {
                    let mergedJSON = try SyncRecords.json(merged)
                    try SyncRecords.apply(["key": key, "payload": merged, "deleted": deleted], context: context)
                    old.payload = try SyncRecords.snapshots(context)[key] ?? mergedJSON
                    old.revision = revision; old.basePayload = value; old.conflict = nil
                    old.dirty = mergedJSON != value
                    if old.dirty { old.mutation = UUID().uuidString.lowercased(); again = true }
                } else { old.conflict = try SyncRecords.json(record) }
                try context.save()
            }
            return
        }
        if let old, old.revision >= revision { return }
        do {
            try SyncRecords.apply(record, context: context)
            let entry = old ?? SyncEntry(key: key, payload: value); if old == nil { context.insert(entry) }
            // Use the local canonical representation to avoid spurious re-uploads.
            entry.payload = try SyncRecords.snapshots(context)[key] ?? value; entry.tombstone = deleted; entry.basePayload = value; entry.revision = revision; entry.dirty = false; entry.conflict = nil; entry.mutation = record["mutation"] as? String ?? UUID().uuidString.lowercased(); try context.save()
        } catch { context.rollback(); throw error }
    }
    func resolve(_ entry: SyncEntry, local: Bool, context: ModelContext) async throws {
        guard !busy, let conflict = entry.conflict else { return }
        let record = try SyncRecords.object(conflict)
        if local { entry.revision = record["revision"] as? Int ?? entry.revision; entry.basePayload = try SyncRecords.json(record["payload"] ?? [:]); entry.conflict = nil; entry.mutation = UUID().uuidString.lowercased(); try context.save() }
        else { entry.dirty = false; entry.revision = 0; try receive(record, context: context) }
        await run(context)
    }
}
