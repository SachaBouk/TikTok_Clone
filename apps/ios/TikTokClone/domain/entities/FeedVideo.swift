import Foundation

// Résumé d'un compte affiché à côté d'un contenu (auteur d'une vidéo, d'un commentaire).
struct UserSummary: Equatable, Hashable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
}

struct VideoStats: Equatable, Sendable {
    let views: Int
    let likes: Int
    let comments: Int
    let favorites: Int
    let shares: Int
    let reposts: Int
}

// Ce que le compte connecté a fait sur la vidéo et son auteur (état des boutons).
struct ViewerState: Equatable, Sendable {
    let liked: Bool
    let favorited: Bool
    let reposted: Bool
    let followingAuthor: Bool
}

// Vidéo publiée telle que lue dans le feed et les grilles (ADR-008 : lecture HLS).
struct FeedVideo: Identifiable, Equatable, Sendable {
    let id: String
    let description: String?
    let hlsURL: URL
    let thumbnailURL: URL
    let createdAt: Date
    let stats: VideoStats
    let author: UserSummary
    // Nil en mode invité.
    let viewer: ViewerState?
    // Anneau autour de l'avatar de l'auteur (ADR-051) : nil s'il n'a pas de story visible.
    var authorStory: StoryRing? = nil
    // Historique de visionnage seulement (ADR-057) : dernière vue de la vidéo.
    var viewedAt: Date? = nil
    // Privée (ADR-061) : seul son auteur la reçoit.
    var visibility: VideoVisibility = .everyone
    // Commentaires autorisés (ADR-062) : coupés, la liste n'est lue que par l'auteur.
    var commentsEnabled = true
}

// Page du feed (ADR-016 : ordre aléatoire propre à une session de scroll).
struct FeedPage: Equatable, Sendable {
    let videos: [FeedVideo]
    // Nil à la fin de la session : repartir sans curseur, sur un nouvel ordre.
    let nextCursor: String?
}
