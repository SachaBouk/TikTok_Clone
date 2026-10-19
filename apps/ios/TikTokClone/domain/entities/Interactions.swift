import Foundation

// Réactions à une vidéo (ADR-016). Le partage est à part : un simple compteur, sans état.
enum ReactionKind: Sendable, CaseIterable {
    case like, favorite, repost
}

// État après une réaction ou un follow : actif ou non, et compteur à jour renvoyé par l'API.
struct InteractionState: Equatable, Sendable {
    let active: Bool
    let count: Int
}

// Commentaire ou réponse (ADR-060 : un seul niveau, `parentID` = commentaire d'origine).
struct VideoComment: Identifiable, Equatable, Sendable {
    let id: String
    let videoID: String
    var parentID: String? = nil
    let content: String
    let createdAt: Date
    let author: UserSummary
    // Réponses du fil (commentaire d'origine), comptes masqués compris.
    var repliesCount = 0
    var likesCount = 0
    // L'auteur de la vidéo l'a aimé (« aimé par l'auteur »).
    var likedByAuthor = false
    // Le compte connecté l'a aimé ; nil en mode invité.
    var viewerLiked: Bool? = nil

    var isReply: Bool { parentID != nil }
}

// Commentaires d'une vidéo (du plus récent au plus ancien), ou réponses d'un fil (de la plus ancienne à la plus récente).
struct CommentPage: Equatable, Sendable {
    let comments: [VideoComment]
    let nextCursor: String?
}

enum CommentRules {
    static let maxLength = 500
    // Barre d'emojis au-dessus du champ, comme TikTok : un toucher ajoute l'emoji au texte.
    static let quickEmojis = ["😁", "🥰", "😂", "😳", "😏", "😅", "🥺"]

    enum DateStyle: Equatable {
        case relative, dayMonth, full
    }

    // Date d'un commentaire, courte comme TikTok : relative la première semaine, puis jour et mois, et l'année si elle diffère.
    static func dateStyle(for date: Date, now: Date, calendar: Calendar = .current) -> DateStyle {
        if now.timeIntervalSince(date) < 7 * 24 * 3600 { return .relative }
        return calendar.component(.year, from: date) == calendar.component(.year, from: now) ? .dayMonth : .full
    }

    // Réponse à une réponse (un seul niveau) : le texte commence par « @pseudo », comme TikTok.
    static func replyPrefix(to comment: VideoComment) -> String {
        comment.isReply ? "@\(comment.author.username) " : ""
    }

    // Texte envoyé (nettoyé), ou nil s'il est vide ou trop long.
    static func sanitized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > maxLength ? nil : trimmed
    }
}

// Lien d'app vers une vidéo (choix du développeur) : tiktokclone://videos/<id>. Les liens universels (https)
// viendront avec l'hébergement (ADR-015).
enum VideoLink {
    static let scheme = "tiktokclone"

    static func url(for videoID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "videos"
        components.path = "/\(videoID)"
        return components.url!
    }

    // Identifiant de la vidéo, ou nil si le lien n'est pas un lien de vidéo.
    static func videoID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "videos" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = parts.first, UUID(uuidString: id) != nil else { return nil }
        return id.lowercased()
    }
}

extension FeedVideo {
    // Garde l'anneau de l'auteur, la date de visionnage, la visibilité et les commentaires.
    func with(stats: VideoStats? = nil, viewer: ViewerState?, visibility: VideoVisibility? = nil, commentsEnabled: Bool? = nil) -> FeedVideo {
        FeedVideo(
            id: id, description: description, hlsURL: hlsURL, thumbnailURL: thumbnailURL, createdAt: createdAt,
            stats: stats ?? self.stats, author: author, viewer: viewer, authorStory: authorStory, viewedAt: viewedAt,
            visibility: visibility ?? self.visibility, commentsEnabled: commentsEnabled ?? self.commentsEnabled)
    }
}

extension VideoStats {
    func with(likes: Int? = nil, comments: Int? = nil, favorites: Int? = nil, shares: Int? = nil, reposts: Int? = nil) -> VideoStats {
        VideoStats(
            views: views, likes: likes ?? self.likes, comments: comments ?? self.comments,
            favorites: favorites ?? self.favorites, shares: shares ?? self.shares, reposts: reposts ?? self.reposts)
    }

    func count(of kind: ReactionKind) -> Int {
        switch kind {
        case .like: likes
        case .favorite: favorites
        case .repost: reposts
        }
    }

    func with(_ kind: ReactionKind, count: Int) -> VideoStats {
        switch kind {
        case .like: with(likes: count)
        case .favorite: with(favorites: count)
        case .repost: with(reposts: count)
        }
    }
}

extension ViewerState {
    static let empty = ViewerState(liked: false, favorited: false, reposted: false, followingAuthor: false)

    func isActive(_ kind: ReactionKind) -> Bool {
        switch kind {
        case .like: liked
        case .favorite: favorited
        case .repost: reposted
        }
    }

    func with(_ kind: ReactionKind, active: Bool) -> ViewerState {
        ViewerState(
            liked: kind == .like ? active : liked,
            favorited: kind == .favorite ? active : favorited,
            reposted: kind == .repost ? active : reposted,
            followingAuthor: followingAuthor
        )
    }

    func with(followingAuthor: Bool) -> ViewerState {
        ViewerState(liked: liked, favorited: favorited, reposted: reposted, followingAuthor: followingAuthor)
    }
}
