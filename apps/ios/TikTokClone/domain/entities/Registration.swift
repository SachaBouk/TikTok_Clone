import Foundation

// Données d'inscription par email (ADR-010, ADR-055). Sign in with Apple viendra avec un compte Apple Developer.
struct Registration: Equatable, Sendable {
    let email: String
    let password: String
    let username: String
    // Nil : le pseudo par défaut (ADR-055), modifiable ensuite dans le profil.
    var displayName: String?
    let birthDate: BirthDate
}

// Date de naissance (ADR-055) : un jour du calendrier, sans heure ni fuseau, envoyé en `AAAA-MM-JJ`.
struct BirthDate: Equatable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    // Jour d'une date dans le calendrier grégorien de l'appareil (celui que montre le sélecteur).
    init(_ date: Date, calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: BirthDate, rhs: BirthDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// Disponibilité d'un pseudo pendant l'inscription (ADR-055).
enum UsernameAvailability: Equatable, Sendable {
    case available
    // Hors des règles du profil.
    case invalid
    case reserved
    case taken
}

// Centre d'intérêt du catalogue de l'API (ADR-055).
struct Interest: Equatable, Identifiable, Sendable {
    let code: String
    let name: String
    let emoji: String

    var id: String { code }
}
