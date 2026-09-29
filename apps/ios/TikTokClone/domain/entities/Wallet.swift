import Foundation

// Portefeuille de jetons (ADR-009). Le solde est tenu par l'API : après un achat validé par le store, RevenueCat
// prévient l'API par webhook, qui crédite le compte puis pousse le solde (`walletUpdated`, ADR-011).

enum WalletTransactionKind: Equatable, Sendable {
    // Achat d'un pack de jetons.
    case purchase
    // Achat remboursé par le store : les jetons sont retirés (jamais sous 0).
    case refund
    // Ajustement manuel (tableau de bord RevenueCat).
    case adjustment

    var title: String {
        switch self {
        case .purchase: "Achat de jetons"
        case .refund: "Remboursement"
        case .adjustment: "Ajustement"
        }
    }
}

struct WalletTransaction: Identifiable, Equatable, Sendable {
    let id: String
    let kind: WalletTransactionKind
    // Variation réelle du solde : positive pour un crédit, négative pour un retrait.
    let amount: Int
    let balanceAfter: Int
    let productID: String?
    let createdAt: Date
}

struct WalletTransactionPage: Equatable, Sendable {
    let transactions: [WalletTransaction]
    let nextCursor: String?
}

// Pack de jetons en vente : produit consommable du store, présenté par l'offre RevenueCat.
struct TokenPack: Identifiable, Equatable, Sendable {
    // Identifiant du package dans l'offre.
    let id: String
    let productID: String
    // Titre et prix localisés par le store (« 100 jetons », « 0,99 € »).
    let title: String
    let price: String
}

enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    case cancelled
}

// Achats impossibles : pas de clé RevenueCat dans cette version de l'app, ou refus du store.
enum PurchaseError: Error, Equatable, Sendable {
    case unavailable
    case failed(String)

    var message: String {
        switch self {
        case .unavailable: "Les achats ne sont pas disponibles dans cette version de l’app."
        case .failed(let reason): "L’achat n’a pas abouti : \(reason)"
        }
    }
}

// Après un achat, le crédit arrive par le webhook de RevenueCat, en général en quelques secondes. Sans événement
// temps réel, le solde est relu après 2, 4, 8 puis 16 s (30 s en tout) ; au-delà, l'app prévient que le crédit
// arrivera plus tard (RevenueCat renvoie le webhook pendant plusieurs heures en cas d'échec).
enum CreditWait {
    static let pollDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16)]
}
