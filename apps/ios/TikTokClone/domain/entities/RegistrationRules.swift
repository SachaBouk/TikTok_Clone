import Foundation

// Règles d'inscription, alignées sur l'API (users/domain/profile-rules.ts, auth.requests.ts) : l'app les
// vérifie avant l'envoi pour des messages immédiats ; l'API reste seule juge (400 / 409).
enum RegistrationRules {
    // Calculée : un Regex n'est pas Sendable, donc pas stockable dans une constante statique en Swift 6.
    static var usernamePattern: Regex<Substring> { /[a-z0-9._]{2,24}/ }
    static let reservedUsernames: Set<String> = ["me"]
    static let displayNameLength = 1...50
    static let passwordLength = 8...128
    static let maxEmailLength = 254

    // Premier problème trouvé, en français, ou nil si l'inscription peut être envoyée.
    static func problem(with registration: Registration) -> String? {
        let email = registration.email.trimmingCharacters(in: .whitespaces)
        if email.isEmpty || !email.contains("@") || email.count > maxEmailLength {
            return "Adresse email invalide."
        }
        if registration.username.wholeMatch(of: usernamePattern) == nil {
            return "Pseudo : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »."
        }
        if reservedUsernames.contains(registration.username) {
            return "Ce pseudo n’est pas disponible."
        }
        if !displayNameLength.contains(registration.displayName.trimmingCharacters(in: .whitespaces).count) {
            return "Nom : 1 à 50 caractères."
        }
        if !passwordLength.contains(registration.password.count) {
            return "Mot de passe : 8 caractères au minimum."
        }
        return nil
    }
}
