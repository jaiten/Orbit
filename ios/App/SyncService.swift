import Foundation
import SwiftData
import SwiftUI
import Security
import WidgetKit

@MainActor final class SyncService: ObservableObject {
    static let shared = SyncService()
    @Published var status = "Saved on this device"
    @Published var email: String?
    private let base = "https://uwcwnjwijvawvvffaxdr.supabase.co"
    private let key = "sb_publishable_m0nf1UT5Q2vLryIVocVbXA_-q5tDD53"
    private var session: [String: Any]?
    private var busy = false
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
    private func request(_ path: String, body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Any {
        var request = URLRequest(url: URL(string: base + path)!); request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "apikey")
        if authenticated, let token = session?["access_token"] as? String { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let value = try JSONSerialization.jsonObject(with: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = value as? [String: Any]; throw NSError(domain: "Orbit", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: error?["msg"] as? String ?? error?["message"] as? String ?? error?["error_description"] as? String ?? "Couldn’t reach sync. Your changes are saved locally."])
        }
        return value
    }
    func signIn(email: String, password: String, create: Bool, context: ModelContext) async throws -> String {
        guard !busy else { return "Sync is finishing. Please try again." }
        let path = create ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password"
        guard let result = try await request(path, body: ["email": email, "password": password], authenticated: false) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        guard result["access_token"] != nil else { return "Check your email to confirm your account, then sign in." }
        guard let user = result["user"] as? [String: Any], let id = user["id"] as? String else { throw CocoaError(.coderReadCorrupt) }
        try SyncRecords.bind(id, context: context); try saveSession(result); await run(context); return "Signed in"
    }
    func signOut() throws { guard !busy else { return }; try saveSession(nil); status = "Saved on this device" }
    func run(_ context: ModelContext) async {
        guard !busy, session != nil else { return }; busy = true; defer { busy = false }
        do {
            if let expires = session?["expires_at"] as? Double, expires < Date.now.timeIntervalSince1970 + 60, let token = session?["refresh_token"] as? String {
                guard let renewed = try await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": token], authenticated: false) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }; try saveSession(renewed)
            }
            guard let user = session?["user"] as? [String: Any], let uid = user["id"] as? String else { throw CocoaError(.coderReadCorrupt) }
            try SyncRecords.bind(uid, context: context); try SyncRecords.capture(context); try context.save(); status = "Syncing…"
            let pending = try context.fetch(FetchDescriptor<SyncEntry>()).filter { $0.dirty && $0.conflict == nil && $0.key != "owner" }
            for entry in pending {
                let mutation = entry.mutation
                let body: [String: Any] = ["p_key": entry.key, "p_payload": try SyncRecords.object(entry.payload), "p_deleted": entry.tombstone, "p_base": entry.revision, "p_mutation": mutation]
                guard let response = try await request("/rest/v1/rpc/orbit_put", body: body) as? [String: Any], let record = response["record"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
                if response["accepted"] as? Bool == true { entry.revision = record["revision"] as? Int ?? entry.revision; if entry.mutation == mutation { entry.dirty = false; entry.conflict = nil }; try context.save() }
                else { try receive(record, context: context) }
            }
            var offset = 0
            while true {
                guard let records = try await request("/rest/v1/orbit_records?select=*&order=key&limit=500&offset=\(offset)") as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
                for record in records { try receive(record, context: context) }
                if records.count < 500 { break }; offset += 500
            }
            let entries = try context.fetch(FetchDescriptor<SyncEntry>())
            status = entries.contains { $0.conflict != nil } ? "Changes need review in Settings" : entries.contains { $0.dirty } ? "Changes waiting to sync" : "All changes synced"
            WidgetCenter.shared.reloadAllTimelines()
            try await refreshReminders(context)
        } catch { status = "Saved locally · " + error.localizedDescription }
    }
    private func receive(_ record: [String: Any], context: ModelContext) throws {
        guard let key = record["key"] as? String, let revision = record["revision"] as? Int, let payload = record["payload"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        let value = try SyncRecords.json(payload), deleted = record["deleted"] as? Bool ?? false
        let old = try context.fetch(FetchDescriptor<SyncEntry>()).first { $0.key == key }
        if let old, old.dirty {
            if revision > old.revision {
                if old.payload == value && old.tombstone == deleted { old.revision = revision; old.dirty = false; old.conflict = nil }
                else { old.conflict = try SyncRecords.json(record) }; try context.save()
            }; return
        }
        if let old, old.revision >= revision { return }
        do {
            try SyncRecords.apply(record, context: context)
            let entry = old ?? SyncEntry(key: key, payload: value); if old == nil { context.insert(entry) }
            // Use the local canonical representation to avoid spurious re-uploads.
            entry.payload = try SyncRecords.snapshots(context)[key] ?? value; entry.tombstone = deleted; entry.revision = revision; entry.dirty = false; entry.conflict = nil; entry.mutation = record["mutation"] as? String ?? UUID().uuidString.lowercased(); try context.save()
        } catch { context.rollback(); throw error }
    }
    func resolve(_ entry: SyncEntry, local: Bool, context: ModelContext) async throws {
        guard !busy, let conflict = entry.conflict else { return }
        let record = try SyncRecords.object(conflict)
        if local { entry.revision = record["revision"] as? Int ?? entry.revision; entry.conflict = nil; entry.mutation = UUID().uuidString.lowercased(); try context.save() }
        else { entry.dirty = false; entry.revision = 0; try receive(record, context: context) }
        await run(context)
    }
}
