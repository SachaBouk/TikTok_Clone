import Foundation

// Écran de profil (ADR-016) : profil, relation avec le compte connecté, grilles, abonnés et abonnements,
// historiques, blocage. Entités du domaine, indépendantes du client généré (ADR-002).

// Relation du compte connecté avec un autre compte (`GET /users/:username/relationship`).
// Qu'un compte ait bloqué le compte connecté n'est jamais révélé.
struct Relationship: Equatable, Sendable {
    var following: Bool
    var followedBy: Bool
    var blockedByMe: Bool

    // Pas `.none` : confondu avec Optional.none sur un `Relationship?`.
    static let empty = Relationship(following: false, followedBy: false, blockedByMe: false)

    // Bouton d'une notification d'abonnement (« Suivre en retour », puis « Ami(e)s ») ; `following` : l'état
    // superposé aux changements faits depuis le chargement. Pas de bouton pour un compte bloqué.
    func followBackStatus(following: Bool) -> FollowStatus? {
        blockedByMe ? nil : FollowStatus(following: following, followedBy: followedBy)
    }
}

// Libellé du bouton d'abonnement, comme TikTok.
enum FollowStatus: Equatable, Sendable {
    case follow
    case followBack
    case following
    case friends

    init(following: Bool, followedBy: Bool) {
        switch (following, followedBy) {
        case (false, false): self = .follow
        case (false, true): self = .followBack
        case (true, false): self = .following
        case (true, true): self = .friends
        }
    }

    var title: String {
        switch self {
        case .follow: "Suivre"
        case .followBack: "Suivre en retour"
        case .following: "Abonné(e)"
        case .friends: "Ami(e)s"
        }
    }

    var isFollowing: Bool { self == .following || self == .friends }
}

// Grilles d'un profil. Favoris et vidéos aimées : sur celui d'un autre aussi, lisibles s'il les a rendus publics, sinon
// un cadenas (ADR-071).
enum ProfileGrid: String, CaseIterable, Hashable, Sendable {
    // `privateVideos` : onglet « cadenas » (ADR-061), sur son propre profil.
    case videos, privateVideos, reposts, favorites, likes

    static func available(isOwn: Bool) -> [ProfileGrid] {
        isOwn ? allCases : [.videos, .reposts, .favorites, .likes]
    }

    var title: String {
        switch self {
        case .videos: "Vidéos"
        case .privateVideos: "Vidéos privées"
        case .reposts: "Republications"
        case .favorites: "Favoris"
        case .likes: "J’aime"
        }
    }

    var systemImage: String {
        switch self {
        case .videos: "square.grid.3x3"
        case .privateVideos: "lock"
        case .reposts: "arrow.2.squarepath"
        case .favorites: "bookmark"
        case .likes: "heart"
        }
    }
}

// Listes de vidéos au format du feed (même lecteur) : grilles et historique de visionnage.
enum VideoList: Hashable, Sendable {
    case accountVideos(username: String)
    case reposts(username: String)
    case myFavorites
    case myLikes
    // Vidéos aimées et favoris d'un autre compte, s'il les a rendus publics (ADR-071).
    case accountLikes(username: String)
    case accountFavorites(username: String)
    case myHistory
    // Ses vidéos privées (ADR-061).
    case myPrivateVideos
    // Page d'un hashtag (ADR-049), sans « # ».
    case hashtag(name: String)
    // Vidéos d'une collection (ADR-072).
    case collection(id: String)

    init(_ grid: ProfileGrid, username: String, isOwn: Bool = true) {
        switch grid {
        case .videos: self = .accountVideos(username: username)
        case .privateVideos: self = .myPrivateVideos
        case .reposts: self = .reposts(username: username)
        case .favorites: self = isOwn ? .myFavorites : .accountFavorites(username: username)
        case .likes: self = isOwn ? .myLikes : .accountLikes(username: username)
        }
    }
}

// Abonnés et abonnements (`GET /users/:username/followers` et `/following`).
enum FollowListKind: Hashable, Sendable {
    case followers, following

    var title: String {
        switch self {
        case .followers: "Abonnés"
        case .following: "Abonnements"
        }
    }
}

struct FollowEntry: Identifiable, Equatable, Sendable {
    var id: String { user.id }
    let user: UserSummary
    let followedAt: Date
    // Relation du compte connecté avec ce compte ; nil en mode invité.
    let viewer: FollowViewer?
}

struct FollowViewer: Equatable, Sendable {
    let following: Bool
    let followedBy: Bool
}

struct FollowPage: Equatable, Sendable {
    let entries: [FollowEntry]
    let nextCursor: String?
}

// Historique des commentaires (centre d'activités, privé).
struct CommentHistoryEntry: Identifiable, Equatable, Sendable {
    struct Video: Equatable, Sendable {
        let id: String
        let thumbnailURL: URL?
        let author: UserSummary
    }

    let id: String
    let content: String
    let createdAt: Date
    let video: Video
}

struct CommentHistoryPage: Equatable, Sendable {
    let entries: [CommentHistoryEntry]
    let nextCursor: String?
}

// Modification du profil : seuls les champs renseignés changent. `bio` ou `pronouns` vide l'efface.
struct ProfileChanges: Equatable, Sendable {
    var username: String?
    var displayName: String?
    var bio: String?
    var pronouns: String?
    // Visibilité des vidéos aimées et des favoris (ADR-071).
    var likesVisibility: VideoVisibility?
    var favoritesVisibility: VideoVisibility?

    var isEmpty: Bool {
        username == nil && displayName == nil && bio == nil && pronouns == nil && likesVisibility == nil && favoritesVisibility == nil
    }
}

// Photo de profil (choix du développeur : l'app recadre en carré de 512 px ; JPEG ou PNG, 5 Mio au plus).
enum AvatarImageType: String, Sendable {
    case jpeg = "image/jpeg"
    case png = "image/png"
}

struct AvatarUpload: Equatable, Sendable {
    let id: String
    let uploadURL: URL
    let expiresAt: Date
}

// Règles du profil, alignées sur l'API (`users/domain/profile-rules.ts`). L'API reste seule juge (400 / 409).
enum ProfileRules {
    static let maxBioLength = 80
    // Pronoms et note de profil (ADR-070).
    static let maxPronounsLength = 20
    static let maxNoteLength = 60
    static let maxAvatarSize = 5 * 1024 * 1024
    static let avatarSide = 512

    // Changements à envoyer (champs nettoyés et réellement modifiés), ou un message si l'un est invalide. `pronouns` nil :
    // inchangés.
    static func changes(
        from profile: UserProfile, username: String, displayName: String, bio: String, pronouns: String? = nil
    ) -> Result<ProfileChanges, AppError> {
        let username = username.trimmingCharacters(in: .whitespaces)
        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)

        if username.wholeMatch(of: RegistrationRules.usernamePattern) == nil {
            return .failure(.rejected("Pseudo : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »."))
        }
        if RegistrationRules.reservedUsernames.contains(username) {
            return .failure(.rejected("Ce pseudo n’est pas disponible."))
        }
        if !RegistrationRules.displayNameLength.contains(displayName.count) {
            return .failure(.rejected("Nom : 1 à 50 caractères."))
        }
        if bio.count > maxBioLength {
            return .failure(.rejected("Bio : \(maxBioLength) caractères au plus."))
        }
        let pronouns = pronouns?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pronouns, pronouns.count > maxPronounsLength {
            return .failure(.rejected("Pronoms : \(maxPronounsLength) caractères au plus."))
        }
        return .success(
            ProfileChanges(
                username: username == profile.username ? nil : username,
                displayName: displayName == profile.displayName ? nil : displayName,
                bio: bio == (profile.bio ?? "") ? nil : bio,
                pronouns: pronouns == nil || pronouns == (profile.pronouns ?? "") ? nil : pronouns
            ))
    }

    // Note nettoyée comme le fait l'API (espaces et retours à la ligne réduits à un espace), ou nil si elle est vide.
    static func cleanedNote(_ text: String) -> String? {
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }
}
