import Foundation

// Règles d'inscription, alignées sur l'API (users/domain/profile-rules.ts, auth/domain/registration-rules.ts) : l'app
// les vérifie avant l'envoi pour des messages immédiats ; l'API reste seule juge (400 / 409).
enum RegistrationRules {
    // Calculée : un Regex n'est pas Sendable, donc pas stockable dans une constante statique en Swift 6.
    static var usernamePattern: Regex<Substring> { /[a-z0-9._]{2,24}/ }
    static let reservedUsernames: Set<String> = ["me"]
    static let maxUsernameLength = 24
    static let displayNameLength = 1...50
    static let passwordLength = 8...128
    static let maxEmailLength = 254
    // ADR-055 : 13 ans au moins, date à partir du 1er janvier 1900.
    static let minimumAge = 13
    static let earliestBirthDate = BirthDate(year: 1900, month: 1, day: 1)
    // Suggestions de domaines sous le champ email, comme TikTok.
    static let emailDomains = ["gmail.com", "icloud.com", "outlook.com", "yahoo.com"]
    // Longueur à partir de laquelle la jauge passe à « Fort », même sans caractère spécial.
    static let strongPasswordLength = 12

    // Premier problème trouvé, en français, ou nil si l'inscription peut être envoyée.
    static func problem(with registration: Registration, today: BirthDate) -> String? {
        if let problem = birthDateProblem(registration.birthDate, today: today) { return problem }
        if !isValidEmail(registration.email) { return "Adresse email invalide." }
        if !isValidPassword(registration.password) {
            return "Mot de passe : 8 caractères au minimum, avec au moins une lettre et un chiffre."
        }
        if let problem = usernameProblem(registration.username) { return problem }
        // Nom vide : le pseudo par défaut.
        if let displayName = registration.displayName?.trimmingCharacters(in: .whitespaces), displayName.count > displayNameLength.upperBound {
            return "Nom : 1 à 50 caractères."
        }
        return nil
    }

    // MARK: Date de naissance

    // Âge en années révolues au jour `today`.
    static func age(of birthDate: BirthDate, on today: BirthDate) -> Int {
        let age = today.year - birthDate.year
        return (today.month, today.day) < (birthDate.month, birthDate.day) ? age - 1 : age
    }

    static func birthDateProblem(_ birthDate: BirthDate, today: BirthDate) -> String? {
        if birthDate < earliestBirthDate || today < birthDate { return "Date de naissance invalide." }
        if age(of: birthDate, on: today) < minimumAge {
            return "Désolé, il faut avoir au moins \(minimumAge) ans pour créer un compte."
        }
        return nil
    }

    // MARK: Email

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= maxEmailLength && trimmed.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    // Saisie complétée par un domaine suggéré : la partie avant « @ » est gardée.
    static func email(_ text: String, completedWith domain: String) -> String {
        let local = text.trimmingCharacters(in: .whitespaces).split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return "\(local)@\(domain)"
    }

    // MARK: Mot de passe

    struct PasswordChecks: Equatable, Sendable {
        var length: Bool
        var letterAndDigit: Bool
        // Conseillé, pas exigé.
        var specialCharacter: Bool
    }

    enum PasswordStrength: Equatable, Sendable {
        case none, weak, medium, strong
    }

    static func checks(for password: String) -> PasswordChecks {
        PasswordChecks(
            length: passwordLength.contains(password.count),
            letterAndDigit: password.contains(where: \.isLetter) && password.contains(where: \.isNumber),
            specialCharacter: password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        )
    }

    static func isValidPassword(_ password: String) -> Bool {
        let checks = checks(for: password)
        return checks.length && checks.letterAndDigit
    }

    // Jauge indicative : faible tant que les règles ne sont pas remplies, moyen quand elles le sont, fort avec en plus
    // un caractère spécial ou 12 caractères.
    static func strength(of password: String) -> PasswordStrength {
        if password.isEmpty { return .none }
        let checks = checks(for: password)
        guard checks.length, checks.letterAndDigit else { return .weak }
        return checks.specialCharacter || password.count >= strongPasswordLength ? .strong : .medium
    }

    // MARK: Pseudo

    static func usernameProblem(_ username: String) -> String? {
        if username.wholeMatch(of: usernamePattern) == nil { return "2 à 24 caractères : lettres minuscules, chiffres, « . » et « _ »." }
        if reservedUsernames.contains(username) { return "Ce pseudo n’est pas disponible." }
        return nil
    }
}
