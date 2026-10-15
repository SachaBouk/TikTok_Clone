import Foundation

// Signalements (ADR-038) : une vidéo, un commentaire, un compte, un message reçu ou une story (ADR-051), avec un motif de la liste et une
// précision facultative. Rien n'est masqué ensuite : un administrateur décide, et la décision arrive dans l'activité.

enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam, harassment, hate, violence, sexual, impersonation, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harcèlement"
        case .hate: "Contenu haineux"
        case .violence: "Violence"
        case .sexual: "Nudité ou contenu sexuel"
        case .impersonation: "Usurpation d’identité"
        case .other: "Autre"
        }
    }

    // Explication affichée sur la page du motif, avant l'envoi (parcours en étapes, comme TikTok).
    var explanation: String {
        switch self {
        case .spam: "Contenu trompeur ou répétitif, faux comptes, liens douteux ou publicités non sollicitées."
        case .harassment: "Moqueries, insultes, menaces ou intimidation qui visent une personne."
        case .hate:
            "Propos ou symboles qui attaquent des personnes pour leur origine, leur religion, leur genre, leur orientation sexuelle, "
                + "leur handicap ou toute autre caractéristique."
        case .violence: "Violence physique, menaces, incitation à la violence, activités dangereuses ou images choquantes."
        case .sexual: "Nudité, contenu sexuel, ou tout contenu qui sexualise un mineur."
        case .impersonation: "Compte ou contenu qui se fait passer pour une autre personne, une marque ou une organisation."
        case .other: "Choisis ce motif si ton signalement ne correspond à aucune des catégories de la liste. Tu peux le préciser ci-dessous."
        }
    }
}

enum ReportTarget: Hashable, Identifiable, Sendable {
    case video(id: String)
    case comment(id: String)
    case account(id: String, username: String)
    case message(id: String)
    case story(id: String)
    case live(id: String)

    var id: String {
        switch self {
        case .video(let id): "video:\(id)"
        case .comment(let id): "comment:\(id)"
        case .account(let id, _): "account:\(id)"
        case .message(let id): "message:\(id)"
        case .story(let id): "story:\(id)"
        case .live(let id): "live:\(id)"
        }
    }

    // Question en tête de la liste des motifs (le titre de la feuille, court, est « Signaler »).
    var question: String {
        switch self {
        case .video: "Pourquoi signaler cette vidéo ?"
        case .comment: "Pourquoi signaler ce commentaire ?"
        case .account(_, let username): "Pourquoi signaler @\(username) ?"
        case .message: "Pourquoi signaler ce message ?"
        case .story: "Pourquoi signaler cette story ?"
        case .live: "Pourquoi signaler ce live ?"
        }
    }

    // Message privé : ce qui est transmis aux administrateurs.
    var privacyNote: String? {
        if case .message = self { return "Seul ce message est transmis à l’équipe de modération, jamais le reste de la conversation." }
        return nil
    }

    // Nom envoyé à la mesure d'audience (ADR-013).
    var analyticsName: String {
        switch self {
        case .video: "video"
        case .comment: "comment"
        case .account: "account"
        case .message: "message"
        case .story: "story"
        case .live: "live"
        }
    }
}

enum ReportRules {
    // Mêmes règles que l'API.
    static let maxDetailsLength = 500

    // Précision nettoyée ; nil si elle est vide.
    static func sanitizedDetails(_ details: String) -> String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
