import Foundation

// Cadeaux en jetons (ADR-050) : envoyés sur une vidéo, débités du solde, crédités aux gains du créateur.

// Cadeau tel que l'API le décrit (nom et emoji ; « 🎁 Cadeau » pour un cadeau retiré du catalogue).
struct GiftInfo: Equatable, Sendable {
    let code: String
    let name: String
    let emoji: String

    var label: String { "\(emoji) \(name)" }
}

// Cadeau du catalogue (`GET /gifts/catalog`), du moins cher au plus cher.
struct GiftCatalogItem: Identifiable, Equatable, Sendable {
    var id: String { info.code }
    let info: GiftInfo
    // Prix en jetons.
    let price: Int

    var priceLabel: String { price == 1 ? "1 jeton" : "\(price) jetons" }
}

// Cadeau envoyé : le cadeau, le prix payé et le solde après le débit.
struct SentGift: Equatable, Sendable {
    let id: String
    let gift: GiftInfo
    let amount: Int
    let balance: Int
}

// Cadeau reçu (`GET /wallet/gifts/received`) : expéditeur et vidéo, nil s'ils ont été supprimés depuis.
struct ReceivedGift: Identifiable, Equatable, Sendable {
    struct Video: Equatable, Sendable {
        let id: String
        let thumbnailURL: URL?
    }

    let id: String
    let gift: GiftInfo
    let amount: Int
    let sender: UserSummary?
    let video: Video?
    let createdAt: Date
}

struct ReceivedGiftPage: Equatable, Sendable {
    let gifts: [ReceivedGift]
    let nextCursor: String?
}

// Animation à l'envoi (choix du développeur : SwiftUI sobre, chez l'expéditeur seulement).
struct GiftBurst: Identifiable, Equatable, Sendable {
    let id = UUID()
    let gift: GiftInfo
    let recipientUsername: String

    // « Rose envoyée à @bob » : accord simple au féminin pour les noms en « e » (Rose, Couronne, Fusée, Étoile).
    var caption: String {
        let sent = gift.name.hasSuffix("e") ? "envoyée" : "envoyé"
        return "\(gift.name) \(sent) à @\(recipientUsername)"
    }
}

// Destinataire d'un cadeau : l'auteur d'une vidéo (ADR-050), ou celui d'un live en cours (ADR-053).
enum GiftTarget: Equatable, Sendable {
    case video(id: String, author: UserSummary)
    case live(id: String, host: UserSummary)

    var recipient: UserSummary {
        switch self {
        case .video(_, let author): author
        case .live(_, let host): host
        }
    }
}
