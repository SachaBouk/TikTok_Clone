import Foundation

// Signalements (ADR-038) : une vidéo, un commentaire ou un compte, avec un motif de la liste et une précision
// facultative. Rien n'est masqué ensuite : un administrateur décide.

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
}

enum ReportTarget: Hashable, Identifiable, Sendable {
    case video(id: String)
    case comment(id: String)
    case account(id: String, username: String)

    var id: String {
        switch self {
        case .video(let id): "video:\(id)"
        case .comment(let id): "comment:\(id)"
        case .account(let id, _): "account:\(id)"
        }
    }

    // Question en tête de la liste des motifs (le titre de la feuille, court, est « Signaler »).
    var question: String {
        switch self {
        case .video: "Pourquoi signaler cette vidéo ?"
        case .comment: "Pourquoi signaler ce commentaire ?"
        case .account(_, let username): "Pourquoi signaler @\(username) ?"
        }
    }

    // Nom envoyé à la mesure d'audience (ADR-013).
    var analyticsName: String {
        switch self {
        case .video: "video"
        case .comment: "comment"
        case .account: "account"
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
