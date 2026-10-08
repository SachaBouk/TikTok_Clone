import Foundation

// Centre d'activité (ADR-016, module notifications de l'API) : une notification par like, commentaire,
// republication ou follow reçu (pas de favori). La boîte de réception les affiche regroupées (`ActivityGroup`).
// S'y ajoutent les décisions de modération (ADR-038), sans auteur : signalement examiné, contenu retiré.
enum ActivityKind: String, Equatable, Sendable {
    // `gift` : cadeau reçu sur une vidéo (ADR-050).
    case like, comment, follow, repost, reportResolved, contentRemoved, gift

    var isModeration: Bool { self == .reportResolved || self == .contentRemoved }
}

// Cadeau reçu (ADR-050) : nom et emoji donnés par l'API (« 🎁 Cadeau » pour un cadeau retiré du catalogue), prix payé.
struct ActivityGift: Equatable, Sendable {
    let name: String
    let emoji: String
    let amount: Int

    var label: String { "\(emoji) \(name)" }
}

// Décision de modération (ADR-038) : à la personne qui a signalé (`outcome`), ou à l'auteur d'un contenu retiré
// (`reason`, motif choisi par l'administrateur). `excerpt` : texte du contenu concerné, copié.
struct ActivityModeration: Equatable, Sendable {
    enum Target: String, Sendable {
        case video, comment, account, message, story
    }

    enum Outcome: String, Sendable {
        case contentRemoved, accountSuspended, dismissed
    }

    let target: Target
    let reason: ReportReason?
    let outcome: Outcome?
    let excerpt: String?

    // Titre en gras de la ligne, comme celui de la notification push.
    func title(_ kind: ActivityKind) -> String {
        kind == .contentRemoved ? "Contenu retiré" : "Signalement examiné"
    }

    // Mêmes textes que les notifications push de l'API.
    func text(_ kind: ActivityKind) -> String {
        if kind == .contentRemoved {
            let removed =
                switch target {
                case .video: "Ta vidéo a été retirée."
                case .comment: "Ton commentaire a été retiré."
                case .message: "Ton message a été retiré."
                case .story: "Ta story a été retirée."
                case .account: "Ton compte a été suspendu."
                }
            // « Autre » : libellé de la liste, peu parlant seul ; même texte que la notification push.
            return reason.map { "\(removed) Motif : \($0 == .other ? "non-respect des règles" : $0.label.lowercased())." } ?? removed
        }
        return switch outcome {
        case .contentRemoved: "Ton signalement a été examiné : le contenu a été retiré."
        case .accountSuspended: "Ton signalement a été examiné : le compte a été suspendu."
        case .dismissed, nil: "Ton signalement a été examiné : aucune infraction constatée."
        }
    }
}

struct ActivityNotification: Identifiable, Equatable, Sendable {
    struct Video: Equatable, Sendable {
        let id: String
        let thumbnailURL: URL?
    }

    struct Comment: Equatable, Sendable {
        let id: String
        let content: String
    }

    let id: String
    let kind: ActivityKind
    // Absent pour une décision de modération.
    let actor: UserSummary?
    // Like, commentaire, republication : la vidéo concernée.
    let video: Video?
    // Commentaire : son texte.
    let comment: Comment?
    let read: Bool
    let createdAt: Date
    // Abonnement : relation du compte connecté avec l'auteur (« Suivre en retour »), lue à part (module interactions,
    // ADR-036) ; nil tant qu'elle n'est pas connue, et pour les autres types.
    var actorRelationship: Relationship? = nil
    // Décision de modération (ADR-038).
    var moderation: ActivityModeration? = nil
    // Cadeau reçu (ADR-050).
    var gift: ActivityGift? = nil

    // Texte affiché après le nom de l'auteur de l'action (le texte entier pour une décision de modération).
    var summary: String {
        switch kind {
        case .like: "a aimé ta vidéo."
        case .comment: "a commenté ta vidéo : \(comment?.content ?? "")"
        case .follow: "a commencé à te suivre."
        case .repost: "a republié ta vidéo."
        case .reportResolved, .contentRemoved: moderation?.text(kind) ?? ""
        case .gift: "t’a envoyé \(gift?.label ?? "un cadeau")."
        }
    }
}

// Notification supprimée, annoncée en direct (ADR-043) : son groupe (`key`, même clé que l'API) est remplacé par son état
// recalculé par l'API, ou retiré s'il est vide.
struct RemovedActivity: Equatable, Sendable {
    let id: String
    let key: String
}

struct ActivityPage: Equatable, Sendable {
    let notifications: [ActivityNotification]
    let nextCursor: String?
}

// Groupe de la boîte de réception, calculé par l'API (choix du développeur, comme TikTok) : like et
// republication par vidéo, tous les follows ensemble, chaque commentaire seul.
struct ActivityGroup: Identifiable, Equatable, Sendable {
    // Clé stable : `like:<videoId>`, `repost:<videoId>`, `follow`, `comment:<notificationId>`,
    // `moderation:<notificationId>`.
    let key: String
    let kind: ActivityKind
    // Auteurs des notifications les plus récentes, 2 au plus, du plus récent au plus ancien ; aucun pour une décision
    // de modération.
    let actors: [UserSummary]
    let count: Int
    let video: ActivityNotification.Video?
    let comment: ActivityNotification.Comment?
    // Faux si au moins une notification du groupe n'est pas lue.
    let read: Bool
    // Notification la plus récente : marquage lu.
    let latestID: String
    let createdAt: Date
    // Abonnement d'un seul compte : relation avec lui (« Suivre en retour »), comme `ActivityNotification`.
    var actorRelationship: Relationship? = nil
    // Décision de modération (ADR-038), toujours seule dans son groupe.
    var moderation: ActivityModeration? = nil
    // Cadeau de la notification la plus récente (ADR-050, cadeaux regroupés par vidéo).
    var gift: ActivityGift? = nil

    var id: String { key }

    // Groupe affiché avec le bouton « Suivre en retour » : un abonnement d'un seul compte.
    var followBackActor: UserSummary? {
        kind == .follow && count == 1 ? actors.first : nil
    }

    // Liste complète du groupe (toucher un groupe de plusieurs notifications) ; nil pour un commentaire.
    var filter: ActivityFilter? {
        switch kind {
        case .like, .repost, .gift: video.map { ActivityFilter(kind: kind, videoID: $0.id) }
        case .follow: ActivityFilter(kind: .follow, videoID: nil)
        case .comment, .reportResolved, .contentRemoved: nil
        }
    }

    // « Inès Moreau », « Inès Moreau et Nathan Petit », « Inès Moreau, Nathan Petit et 3 autres ».
    var actorNames: String {
        if kind.isModeration, let moderation { return moderation.title(kind) }
        let names = actors.map(\.displayName)
        // Cadeaux : `count` compte les cadeaux, pas les comptes (un compte peut en envoyer plusieurs).
        if kind == .gift { return names.count == 2 ? "\(names[0]) et \(names[1])" : names.first ?? "Un compte" }
        let others = count - names.count
        switch (names.count, others) {
        case (0, _): return "\(count) comptes"
        case (1, 0): return names[0]
        case (2, 0): return "\(names[0]) et \(names[1])"
        case (_, 1): return "\(names.joined(separator: ", ")) et 1 autre"
        default: return "\(names.joined(separator: ", ")) et \(others) autres"
        }
    }

    // Texte après les noms, accordé au nombre.
    var summary: String {
        let plural = count > 1
        switch kind {
        case .like: return plural ? "ont aimé ta vidéo." : "a aimé ta vidéo."
        case .comment: return "a commenté ta vidéo : \(comment?.content ?? "")"
        case .follow: return plural ? "ont commencé à te suivre." : "a commencé à te suivre."
        case .repost: return plural ? "ont republié ta vidéo." : "a republié ta vidéo."
        case .reportResolved, .contentRemoved: return moderation?.text(kind) ?? ""
        case .gift:
            guard plural else { return "t’a envoyé \(gift?.label ?? "un cadeau")." }
            return actors.count > 1 ? "t’ont envoyé \(count) cadeaux." : "t’a envoyé \(count) cadeaux."
        }
    }

    // Clé du groupe d'une notification, comme l'API.
    static func key(for notification: ActivityNotification) -> String {
        switch notification.kind {
        case .like, .repost, .gift: "\(notification.kind.rawValue):\(notification.video?.id ?? "")"
        case .follow: "follow"
        case .comment: "comment:\(notification.id)"
        case .reportResolved, .contentRemoved: "moderation:\(notification.id)"
        }
    }

    // Notification reçue en direct : son groupe, mis à jour (une notification de plus, non lu, auteur en tête),
    // ou un nouveau groupe.
    static func merging(_ notification: ActivityNotification, into existing: ActivityGroup?) -> ActivityGroup {
        guard let existing else {
            return ActivityGroup(
                key: key(for: notification), kind: notification.kind, actors: notification.actor.map { [$0] } ?? [], count: 1,
                video: notification.video, comment: notification.comment, read: notification.read,
                latestID: notification.id, createdAt: notification.createdAt, actorRelationship: notification.actorRelationship,
                moderation: notification.moderation, gift: notification.gift
            )
        }
        let actors = (notification.actor.map { [$0] } ?? []) + existing.actors.filter { $0.id != notification.actor?.id }
        return ActivityGroup(
            key: existing.key, kind: existing.kind, actors: Array(actors.prefix(2)), count: existing.count + 1,
            video: notification.video ?? existing.video, comment: existing.comment, read: existing.read && notification.read,
            latestID: notification.id, createdAt: notification.createdAt, gift: notification.gift ?? existing.gift
        )
    }
}

struct ActivityGroupPage: Equatable, Sendable {
    let groups: [ActivityGroup]
    let nextCursor: String?
}

// Liste complète d'un groupe : son type, et sa vidéo pour un like ou une republication.
struct ActivityFilter: Hashable, Sendable {
    let kind: ActivityKind
    let videoID: String?

    var title: String {
        switch kind {
        case .like: "J’aime"
        case .comment: "Commentaires"
        case .follow: "Nouveaux abonnés"
        case .repost: "Republications"
        case .reportResolved, .contentRemoved: "Modération"
        case .gift: "Cadeaux"
        }
    }
}
