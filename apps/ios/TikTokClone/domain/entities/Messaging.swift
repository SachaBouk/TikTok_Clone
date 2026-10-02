import Foundation

// Messagerie directe (ADR-016, module messaging de l'API) : conversations à deux, messages texte ou vidéo
// partagée, demandes de message, « Vu » et « en train d'écrire ».

// Statut de la conversation pour le compte connecté.
enum ConversationStatus: Equatable, Sendable {
    // Conversation acceptée, ou abonnés mutuels : envoi libre.
    case direct
    // Demande envoyée, pas encore acceptée : quelques messages au plus (`remainingRequestMessages`).
    case requestSent
    // Demande reçue : accepter, refuser, ou répondre (ce qui l'accepte).
    case requestReceived
}

// Vidéo partagée dans un message ; `available` faux si elle a été supprimée depuis (autres champs nuls).
struct SharedVideo: Equatable, Sendable {
    let id: String
    let available: Bool
    let thumbnailURL: URL?
    let description: String?
    let author: UserSummary?
}

struct DirectMessage: Identifiable, Equatable, Sendable {
    // UUID v7 : l'ordre des identifiants est l'ordre d'envoi.
    let id: String
    let conversationID: String
    let senderID: String
    // Vide si le message ne fait que partager une vidéo.
    let content: String
    let sharedVideo: SharedVideo?
    let createdAt: Date

    // Aperçu d'une ligne de la boîte de réception.
    func preview(ownID: String?) -> String {
        let text = content.isEmpty ? "Vidéo partagée" : content
        return senderID == ownID ? "Toi : \(text)" : text
    }
}

struct Conversation: Identifiable, Equatable, Sendable {
    let id: String
    let participant: UserSummary
    var status: ConversationStatus
    var lastMessage: DirectMessage?
    // Messages de l'autre participant non lus.
    var unreadCount: Int
    // Dernier message lu par l'autre (« Vu ») ; nil tant que la conversation n'est pas acceptée.
    var participantLastReadMessageID: String?
    // Faux en cas de blocage (dans un sens ou l'autre) ou de demande envoyée épuisée.
    var canSend: Bool
    // Demande envoyée : messages encore possibles avant acceptation ; nil sinon.
    var remainingRequestMessages: Int?
    // C'est le compte connecté qui bloque l'autre.
    var blockedByMe: Bool
    let createdAt: Date

    // « En train d'écrire » n'est relayé que dans une conversation libre, sans blocage (règle de l'API).
    var allowsTyping: Bool { status == .direct && canSend }

    // Pourquoi on ne peut pas (ou plus) écrire, ou ce qu'il faut savoir avant d'écrire.
    var composerNotice: String? {
        let name = "@\(participant.username)"
        if !canSend {
            if blockedByMe { return "Tu as bloqué \(name). Débloque ce compte depuis son profil pour lui écrire." }
            if status == .requestSent { return "Demande envoyée. Tu pourras écrire à nouveau quand \(name) l’aura acceptée." }
            return "Tu ne peux pas écrire à ce compte."
        }
        if status == .requestSent, let remaining = remainingRequestMessages {
            let messages = remaining > 1 ? "\(remaining) messages" : "\(remaining) message"
            return "Vous ne vous suivez pas mutuellement : ta demande à \(name) pourra contenir encore \(messages) tant qu’elle n’est pas acceptée."
        }
        return nil
    }

    // Message envoyé par le compte connecté : la demande consomme une place, répondre à une demande l'accepte.
    func afterSending(_ message: DirectMessage) -> Conversation {
        var copy = self
        copy.lastMessage = message
        copy.unreadCount = 0
        switch status {
        case .requestSent:
            if let remaining = remainingRequestMessages {
                copy.remainingRequestMessages = max(0, remaining - 1)
                copy.canSend = canSend && remaining > 1
            }
        case .requestReceived:
            copy.status = .direct
        case .direct:
            break
        }
        return copy
    }
}

struct ConversationPage: Equatable, Sendable {
    let conversations: [Conversation]
    let nextCursor: String?
}

struct MessagePage: Equatable, Sendable {
    // Du plus récent au plus ancien, comme l'API.
    let messages: [DirectMessage]
    let nextCursor: String?
}

// Badges de la messagerie, renvoyés par l'API et avec chaque événement temps réel.
struct MessagingBadges: Equatable, Sendable {
    // Conversations acceptées ayant au moins un message non lu.
    var unreadConversations: Int
    // Demandes reçues en attente.
    var pendingRequests: Int

    static let zero = MessagingBadges(unreadConversations: 0, pendingRequests: 0)
}

enum MessageRules {
    static let maxLength = 1000
    // « En train d'écrire » : envoyé toutes les ~3 s pendant la saisie ; affiché ~5 s sans nouvel événement.
    static let typingInterval: Duration = .seconds(3)
    static let typingDisplay: Duration = .seconds(5)
    // Un horodatage est affiché avant un message envoyé plus d'une heure après le précédent.
    static let timestampGap: TimeInterval = 3600

    // Texte nettoyé comme l'API ; nil s'il est vide.
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isValid(_ text: String) -> Bool {
        guard let cleaned = cleaned(text) else { return false }
        return cleaned.count <= maxLength
    }

    // Identifiants UUID v7 : comparés en texte, ils suivent l'ordre d'envoi.
    static func isAtOrBefore(_ id: String, _ other: String) -> Bool {
        id.lowercased() <= other.lowercased()
    }

    // « Vu » : sous le dernier message envoyé par le compte connecté, s'il a été lu par l'autre.
    static func seenMessageID(in messages: [DirectMessage], ownID: String, participantLastRead: String?) -> String? {
        guard let lastRead = participantLastRead,
            let lastOwn = messages.last(where: { $0.senderID == ownID }),
            isAtOrBefore(lastOwn.id, lastRead)
        else { return nil }
        return lastOwn.id
    }

    // Messages (du plus ancien au plus récent) avant lesquels afficher un horodatage.
    static func timestampedIDs(in messages: [DirectMessage]) -> Set<String> {
        var result = Set<String>()
        var previous: Date?
        for message in messages {
            if previous.map({ message.createdAt.timeIntervalSince($0) >= timestampGap }) ?? true { result.insert(message.id) }
            previous = message.createdAt
        }
        return result
    }
}
