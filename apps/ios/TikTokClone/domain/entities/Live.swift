import Foundation

// Live (ADR-053) : un compte filme en direct ; la vidéo passe par le serveur LiveKit, jamais par l'API. Chat, cœurs et
// cadeaux passent par l'API, qui les diffuse dans la salle. Pas de replay : à sa fin, le live disparaît.

enum LiveStatus: String, Equatable, Sendable {
    case live, ended
}

enum LiveEndReason: String, Equatable, Sendable {
    case host, timeLimit, disconnected, moderation, suspension

    // Texte affiché aux spectateurs à la fin du live.
    var message: String {
        switch self {
        case .host, .disconnected: "Le live est terminé."
        case .timeLimit: "Le live est terminé : 2 heures au plus."
        case .moderation, .suspension: "Ce live a été arrêté par la modération."
        }
    }
}

// Chiffres d'un live, pour son auteur seulement.
struct LiveStats: Equatable, Sendable {
    let durationSeconds: Int
    let peakViewers: Int
    let viewersCount: Int
    let heartsCount: Int
    let giftsCount: Int
    let giftsAmount: Int

    var durationLabel: String {
        Duration.seconds(durationSeconds).formatted(.time(pattern: durationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

struct LiveStream: Identifiable, Equatable, Sendable {
    let id: String
    let host: UserSummary
    let title: String?
    let status: LiveStatus
    let startedAt: Date
    let endedAt: Date?
    let endReason: LiveEndReason?
    // Pour l'auteur seulement.
    var stats: LiveStats? = nil

    var isLive: Bool { status == .live }
}

struct LiveChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let liveID: String
    let user: UserSummary
    let content: String
    let createdAt: Date
}

enum LiveRole: Equatable, Sendable {
    // Publie sa caméra et son micro.
    case host
    // Regarde seulement (invité compris).
    case viewer
}

// Accès à la salle du serveur vidéo, délivré par l'API.
struct LiveConnection: Equatable, Sendable {
    let live: LiveStream
    let role: LiveRole
    let url: URL
    let token: String
    // Derniers messages du chat, du plus ancien au plus récent.
    let recentMessages: [LiveChatMessage]
}

// Événement diffusé dans la salle par l'API (messages de données de LiveKit, sujet `live`).
enum LiveRoomEvent: Equatable, Sendable {
    case chatMessage(LiveChatMessage)
    case chatMessageDeleted(id: String)
    case hearts(count: Int, total: Int)
    case gift(sender: UserSummary, gift: GiftInfo, amount: Int, giftsCount: Int, giftsAmount: Int)
    case ended(LiveEndReason)
}

// Règles du live (mêmes valeurs que l'API, `live/domain/live.ts`).
enum LiveRules {
    static let maxTitleLength = 80
    static let maxMessageLength = 150
    // Cœurs envoyés par lots : au plus ce nombre par requête, une requête par seconde au plus.
    static let maxHeartsPerBatch = 30
    static let heartsFlushDelay: Duration = .seconds(1)
    // Messages gardés à l'écran.
    static let maxChatMessages = 100

    // Titre nettoyé ; nil s'il est vide.
    static func sanitizedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Message nettoyé ; nil s'il est vide ou trop long.
    static func sanitizedMessage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxMessageLength else { return nil }
        return trimmed
    }
}

// Chat affiché : messages dans l'ordre, sans doublon (réponse à l'envoi et écho de la salle), retraits appliqués, les
// plus anciens oubliés au-delà de la limite.
struct LiveChat: Equatable, Sendable {
    private(set) var messages: [LiveChatMessage] = []

    init(_ messages: [LiveChatMessage] = []) {
        for message in messages { append(message) }
    }

    mutating func append(_ message: LiveChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        if messages.count > LiveRules.maxChatMessages { messages.removeFirst(messages.count - LiveRules.maxChatMessages) }
    }

    mutating func remove(id: String) {
        messages.removeAll { $0.id == id }
    }

    // Messages des comptes bloqués par l'app, retirés de l'affichage (le chat est diffusé à toute la salle).
    func hiding(_ userIDs: Set<String>) -> [LiveChatMessage] {
        userIDs.isEmpty ? messages : messages.filter { !userIDs.contains($0.user.id) }
    }
}

// Touchers sur le cœur, envoyés par lots : au plus `maxHeartsPerBatch` par envoi, le reste au suivant.
struct HeartBatch: Equatable, Sendable {
    private(set) var pending = 0

    mutating func tap() {
        pending += 1
    }

    // Lot à envoyer maintenant (nil s'il n'y en a pas).
    mutating func take() -> Int? {
        guard pending > 0 else { return nil }
        let count = min(pending, LiveRules.maxHeartsPerBatch)
        pending -= count
        return count
    }
}

// Lien d'app vers un live (partage) : tiktokclone://lives/<id>.
enum LiveLink {
    static func url(for liveID: String) -> URL {
        var components = URLComponents()
        components.scheme = VideoLink.scheme
        components.host = "lives"
        components.path = "/\(liveID)"
        return components.url!
    }

    static func liveID(from url: URL) -> String? {
        guard url.scheme == VideoLink.scheme, url.host == "lives" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = parts.first, UUID(uuidString: id) != nil else { return nil }
        return id.lowercased()
    }
}

// D'où un live a été ouvert (mesure d'audience, ADR-013).
enum LiveSource: String, Equatable, Sendable {
    case tray
    case profile
    case activity
    case message
    case link
}
