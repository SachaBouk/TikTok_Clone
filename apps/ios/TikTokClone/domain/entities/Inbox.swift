import Foundation

// Onglet « Messages », comme TikTok (ADR-058) : comptes suggérés, recherche dans les messages, filtre de l'activité.

// Compte suggéré : amis d'amis et abonnés que l'on ne suit pas (API, sans comptes bloqués ni suspendus).
struct AccountSuggestion: Identifiable, Equatable, Sendable {
    let user: UserSummary
    let followersCount: Int
    // Ce compte suit le compte connecté.
    let followsYou: Bool
    // Comptes que l'on suit et qui suivent ce compte (3 au plus), et leur nombre.
    let followedBy: [UserSummary]
    let followedByCount: Int

    var id: String { user.id }

    // Ligne sous le nom : « Te suit », « Suivi(e) par » (les photos suivent, et « +N » au-delà), ou une suggestion simple.
    var reason: String {
        if followsYou { return "Te suit" }
        if followedByCount > 0 { return "Suivi(e) par" }
        return "Suggéré pour toi"
    }

    // « +N » après les photos affichées.
    var moreFollowedBy: Int { max(0, followedByCount - followedBy.count) }
}

// Suggestions écartées (×) : gardées sur l'appareil, oubliées à chaque changement de session.
struct DismissedSuggestions: Equatable, Sendable {
    // Au-delà, les plus anciennes sont oubliées (et peuvent revenir).
    static let maxEntries = 200

    private(set) var ids: [String]

    init(_ ids: [String] = []) {
        self.ids = Array(ids.suffix(Self.maxEntries))
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    mutating func dismiss(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.append(id)
        ids = Array(ids.suffix(Self.maxEntries))
    }
}

// Message trouvé par la recherche : il ouvre sa conversation.
struct MessageSearchResult: Identifiable, Equatable, Sendable {
    let conversationID: String
    let messageID: String
    let content: String
    let createdAt: Date
    // L'autre participant de la conversation ; dans un groupe, l'expéditeur.
    let participant: UserSummary
    let sender: UserSummary
    // Message d'un groupe (ADR-059) : son nom et ses membres.
    var group: (name: String?, members: [UserSummary])? = nil

    var id: String { messageID }

    // Nom affiché : l'autre participant, ou le groupe (sinon les noms de ses autres membres).
    func title(ownID: String?) -> String {
        guard let group else { return participant.displayName }
        return group.name ?? GroupRules.names(group.members.filter { $0.id != ownID }.map(\.displayName))
    }

    static func == (lhs: MessageSearchResult, rhs: MessageSearchResult) -> Bool {
        lhs.messageID == rhs.messageID && lhs.content == rhs.content && lhs.participant == rhs.participant && lhs.sender == rhs.sender
            && lhs.group?.name == rhs.group?.name && lhs.group?.members == rhs.group?.members
    }
}

// Filtre « Activité ▾ » : les abonnements sont à part, dans « Nouveaux followers ».
enum ActivityTypeFilter: CaseIterable, Hashable, Sendable {
    case all, likes, comments, mentions, reposts, gifts, lives, moderation

    var title: String {
        switch self {
        case .all: "Toute l’activité"
        case .likes: "J’aime"
        case .comments: "Commentaires"
        case .mentions: "Mentions"
        case .reposts: "Republications"
        case .gifts: "Cadeaux"
        case .lives: "Lives"
        case .moderation: "Modération"
        }
    }

    // Types demandés à l'API.
    var kinds: [ActivityKind] {
        switch self {
        case .all: ActivityKind.allCases.filter { $0 != .follow }
        case .likes: [.like, .commentLike]
        case .comments: [.comment, .commentReply, .mention]
        // Mentions dans un commentaire (ADR-060) ou dans la description d'une vidéo (ADR-065).
        case .mentions: [.mention, .videoMention]
        case .reposts: [.repost]
        case .gifts: [.gift]
        case .lives: [.live]
        case .moderation: [.reportResolved, .contentRemoved]
        }
    }

    func includes(_ kind: ActivityKind) -> Bool { kinds.contains(kind) }
}
