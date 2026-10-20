import Foundation
import CryptoKit
import Security

enum RecoveryFlow {
    static func code(from url: URL) -> String? {
        guard url.scheme == "orbit", url.host == "auth", url.user == nil, url.password == nil, url.path.isEmpty || url.path == "/",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              code.range(of: #"^[A-Za-z0-9_-]{16,2048}$"#, options: .regularExpression) != nil else { return nil }
        return code
    }
    static func challenge(_ verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func create(email: String) throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CocoaError(.coderInvalidValue) }
        let verifier = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let data = try JSONSerialization.data(withJSONObject: ["verifier": verifier, "email": email, "created": Date.now.timeIntervalSince1970])
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "OrbitRecovery"]
        SecItemDelete(query as CFDictionary)
        guard SecItemAdd(query.merging([kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, value in value } as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        return challenge(verifier)
    }
    static func pending() throws -> (verifier: String, email: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "OrbitRecovery", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let p = try JSONSerialization.jsonObject(with: data) as? [String: Any], let created = p["created"] as? Double, Date.now.timeIntervalSince1970 - created < 3600, let verifier = p["verifier"] as? String, let email = p["email"] as? String else {
            throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request a new recovery email on this device, then open its link here."])
        }
        return (verifier, email)
    }
    static func clear() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "OrbitRecovery"] as CFDictionary) }
}
