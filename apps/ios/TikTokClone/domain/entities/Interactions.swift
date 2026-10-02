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

struct VideoComment: Identifiable, Equatable, Sendable {
    let id: String
    let videoID: String
    let content: String
    let createdAt: Date
    let author: UserSummary
}

struct CommentPage: Equatable, Sendable {
    let comments: [VideoComment]
    let nextCursor: String?
}

enum CommentRules {
    static let maxLength = 500

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
    func with(stats: VideoStats? = nil, viewer: ViewerState?) -> FeedVideo {
        FeedVideo(
            id: id, description: description, hlsURL: hlsURL, thumbnailURL: thumbnailURL, createdAt: createdAt,
            stats: stats ?? self.stats, author: author, viewer: viewer)
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
