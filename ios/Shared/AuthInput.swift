import Foundation

enum AuthInput {
    /// A basic form check; the authentication service remains responsible for acceptance.
    static func validEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$"#, options: .regularExpression) != nil
    }
}
