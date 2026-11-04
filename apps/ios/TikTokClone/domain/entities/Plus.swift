import Foundation

// Abonnement « Plus » (ADR-073) : mensuel ou annuel, acheté par RevenueCat. L'API tient l'état (webhook) et donne les
// avantages : badge « + », jetons offerts, cadeaux exclusifs, vidéos de 10 minutes et lives de 4 heures ; les icônes de
// l'app au choix se règlent sur l'iPhone.

enum PlusPeriod: String, Equatable, Sendable {
    case monthly
    case annual

    var title: String {
        switch self {
        case .monthly: "Mensuel"
        case .annual: "Annuel"
        }
    }
}

// État renvoyé par l'API (`GET /users/me/plus`, événement `plusChanged`).
struct PlusStatus: Equatable, Sendable {
    let isActive: Bool
    var period: PlusPeriod?
    // Échéance, période de grâce comprise.
    var expiresAt: Date?
    // Faux : renouvellement annulé, actif jusqu'à l'échéance.
    var willRenew: Bool?

    static let none = PlusStatus(isActive: false)

    // Actif maintenant : l'échéance peut passer pendant que l'app est ouverte.
    func isActive(at date: Date) -> Bool {
        isActive && (expiresAt.map { $0 > date } ?? true)
    }
}

// Offre de l'offre « plus » de RevenueCat (`$rc_monthly`, `$rc_annual`), prix localisés par le store.
struct PlusOffer: Identifiable, Equatable, Sendable {
    // Identifiant du package dans l'offre.
    let id: String
    let productID: String
    let period: PlusPeriod
    // « 4,99 € », « 39,99 € ».
    let price: String
    let priceValue: Decimal
    // Prix ramené au mois (« 3,33 € »), pour l'annuel.
    let pricePerMonth: String?
}

enum PlusRules {
    static let maxVideoDuration: Duration = .seconds(600)
    static let maxFileSize = 2 * 1024 * 1024 * 1024  // 2 Gio
    // Jetons offerts par RevenueCat à la souscription et à chaque renouvellement.
    static let monthlyTokens = 150
    static let annualTokens = 1800
    // Icônes de l'app réservées aux abonnés.
    static let appIcons = AppIcon.allCases

    // Économie de l'annuel sur douze mois du mensuel, en pourcentage arrondi à l'unité inférieure ; nil sans économie.
    static func annualSavingsPercent(monthly: PlusOffer, annual: PlusOffer) -> Int? {
        let yearOfMonthly = monthly.priceValue * 12
        guard yearOfMonthly > 0, annual.priceValue < yearOfMonthly else { return nil }
        let ratio = NSDecimalNumber(decimal: (yearOfMonthly - annual.priceValue) / yearOfMonthly).doubleValue
        let percent = Int((ratio * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    // Offres dans l'ordre du paywall : annuelle d'abord (mise en avant), puis mensuelle.
    static func ordered(_ offers: [PlusOffer]) -> [PlusOffer] {
        offers.sorted { ($0.period == .annual ? 0 : 1) < ($1.period == .annual ? 0 : 1) }
    }
}

// Icônes de l'app au choix (ADR-073), dérivées du logo maison. `nil` (icône d'origine) n'est pas un cas : c'est l'absence de choix.
enum AppIcon: String, CaseIterable, Identifiable, Equatable, Sendable {
    case gold = "AppIconGold"
    case neon = "AppIconNeon"
    case retro = "AppIconRetro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gold: "Or"
        case .neon: "Néon"
        case .retro: "Rétro"
        }
    }
}
