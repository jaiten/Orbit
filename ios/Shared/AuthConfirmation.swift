import Foundation

/// The server confirms the email before redirecting. Session tokens in links are
/// deliberately ignored; users sign in with their password on each device.
enum AuthConfirmation {
    static func notice(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "orbit", url.host?.lowercased() == "auth", url.path.isEmpty || url.path == "/" else { return nil }
        let fragment = URLComponents(string: "?" + (url.fragment ?? ""))?.queryItems ?? []
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if (fragment + query).contains(where: { $0.name == "error" || $0.name == "error_code" }) {
            return "That confirmation link is invalid or expired. Request a fresh email in Settings and use the newest link."
        }
        return "Your email link has returned to Orbit. Sign in with your email and password to start syncing."
    }
}
