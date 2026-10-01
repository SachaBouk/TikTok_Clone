import Foundation

// Centre d'activité (ADR-016, module notifications de l'API) : une notification par like, commentaire,
// republication ou follow reçu (pas de favori). La boîte de réception les affiche regroupées (`ActivityGroup`).
enum ActivityKind: String, Equatable, Sendable {
    case like, comment, follow, repost
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
    let actor: UserSummary
    // Like, commentaire, republication : la vidéo concernée.
    let video: Video?
    // Commentaire : son texte.
    let comment: Comment?
    let read: Bool
    let createdAt: Date
    // Abonnement : relation du compte connecté avec l'auteur (« Suivre en retour »), lue à part (module interactions,
    // ADR-036) ; nil tant qu'elle n'est pas connue, et pour les autres types.
    var actorRelationship: Relationship? = nil

    // Texte affiché après le nom de l'auteur de l'action.
    var summary: String {
        switch kind {
        case .like: "a aimé ta vidéo."
        case .comment: "a commenté ta vidéo : \(comment?.content ?? "")"
        case .follow: "a commencé à te suivre."
        case .repost: "a republié ta vidéo."
        }
    }
}

struct ActivityPage: Equatable, Sendable {
    let notifications: [ActivityNotification]
    let nextCursor: String?
}

// Groupe de la boîte de réception, calculé par l'API (choix du développeur, comme TikTok) : like et
// republication par vidéo, tous les follows ensemble, chaque commentaire seul.
struct ActivityGroup: Identifiable, Equatable, Sendable {
    // Clé stable : `like:<videoId>`, `repost:<videoId>`, `follow`, `comment:<notificationId>`.
    let key: String
    let kind: ActivityKind
    // Auteurs des notifications les plus récentes, 2 au plus, du plus récent au plus ancien.
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

    var id: String { key }

    // Groupe affiché avec le bouton « Suivre en retour » : un abonnement d'un seul compte.
    var followBackActor: UserSummary? {
        kind == .follow && count == 1 ? actors.first : nil
    }

    // Liste complète du groupe (toucher un groupe de plusieurs notifications) ; nil pour un commentaire.
    var filter: ActivityFilter? {
        switch kind {
        case .like, .repost: video.map { ActivityFilter(kind: kind, videoID: $0.id) }
        case .follow: ActivityFilter(kind: .follow, videoID: nil)
        case .comment: nil
        }
    }

    // « Inès Moreau », « Inès Moreau et Nathan Petit », « Inès Moreau, Nathan Petit et 3 autres ».
    var actorNames: String {
        let names = actors.map(\.displayName)
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
        }
    }

    // Clé du groupe d'une notification, comme l'API.
    static func key(for notification: ActivityNotification) -> String {
        switch notification.kind {
        case .like, .repost: "\(notification.kind.rawValue):\(notification.video?.id ?? "")"
        case .follow: "follow"
        case .comment: "comment:\(notification.id)"
        }
    }

    // Notification reçue en direct : son groupe, mis à jour (une notification de plus, non lu, auteur en tête),
    // ou un nouveau groupe.
    static func merging(_ notification: ActivityNotification, into existing: ActivityGroup?) -> ActivityGroup {
        guard let existing else {
            return ActivityGroup(
                key: key(for: notification), kind: notification.kind, actors: [notification.actor], count: 1,
                video: notification.video, comment: notification.comment, read: notification.read,
                latestID: notification.id, createdAt: notification.createdAt, actorRelationship: notification.actorRelationship
            )
        }
        let actors = [notification.actor] + existing.actors.filter { $0.id != notification.actor.id }
        return ActivityGroup(
            key: existing.key, kind: existing.kind, actors: Array(actors.prefix(2)), count: existing.count + 1,
            video: notification.video ?? existing.video, comment: existing.comment, read: existing.read && notification.read,
            latestID: notification.id, createdAt: notification.createdAt
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
        }
    }
}
