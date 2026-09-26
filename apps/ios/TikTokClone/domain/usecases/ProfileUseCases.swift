import Foundation

// Cas d'usage de l'écran de profil (ADR-002, ADR-016).

struct LoadProfileUseCase: Sendable {
    let profiles: any ProfileRepository

    func callAsFunction(username: String) async throws -> UserProfile {
        try await profiles.profile(username: username)
    }
}

struct LoadRelationshipUseCase: Sendable {
    let relationships: any RelationshipRepository

    func callAsFunction(username: String) async throws -> Relationship {
        try await relationships.relationship(username: username)
    }
}

// Vérifie les champs (règles de l'API) et n'envoie que ceux qui ont changé.
struct UpdateProfileUseCase: Sendable {
    let profiles: any ProfileRepository

    // Renvoie le profil inchangé s'il n'y a rien à envoyer.
    func callAsFunction(_ profile: UserProfile, username: String, displayName: String, bio: String) async throws -> UserProfile {
        let changes = try ProfileRules.changes(from: profile, username: username, displayName: displayName, bio: bio).get()
        guard !changes.isEmpty else { return profile }
        return try await profiles.updateMyProfile(changes)
    }
}

// Photo de profil en trois temps : URL signée, envoi direct au stockage, installation par l'API.
struct ChangeAvatarUseCase: Sendable {
    let profiles: any ProfileRepository
    let transport: any AvatarUploadTransport

    // `data` : image déjà recadrée et encodée (JPEG ou PNG).
    func callAsFunction(_ data: Data, type: AvatarImageType) async throws -> UserProfile {
        guard !data.isEmpty, data.count <= ProfileRules.maxAvatarSize else {
            throw AppError.rejected("La photo dépasse 5 Mo.")
        }
        let upload = try await profiles.createAvatarUpload(type: type, size: data.count)
        try await transport.upload(data, type: type, to: upload.uploadURL)
        return try await profiles.setAvatar(id: upload.id)
    }
}

struct RemoveAvatarUseCase: Sendable {
    let profiles: any ProfileRepository

    func callAsFunction() async throws -> UserProfile {
        try await profiles.removeAvatar()
    }
}

// Suppression définitive du compte (exigence Apple), puis oubli de la session sur l'appareil.
struct DeleteAccountUseCase: Sendable {
    let profiles: any ProfileRepository
    let auth: any AuthRepository

    func callAsFunction() async throws {
        try await profiles.deleteAccount()
        await auth.logout()
    }
}

struct LoadFollowsUseCase: Sendable {
    let relationships: any RelationshipRepository

    func callAsFunction(_ kind: FollowListKind, username: String, cursor: String?) async throws -> FollowPage {
        try await relationships.follows(kind, username: username, cursor: cursor)
    }
}

struct SetBlockedUseCase: Sendable {
    let relationships: any RelationshipRepository

    func callAsFunction(_ blocked: Bool, username: String) async throws {
        try await relationships.setBlocked(blocked, username: username)
    }
}

struct LoadBlockedUsersUseCase: Sendable {
    let relationships: any RelationshipRepository

    func callAsFunction() async throws -> [UserSummary] {
        try await relationships.blockedUsers()
    }
}

// Une page d'une liste de vidéos (grille d'un profil, historique).
struct LoadVideoPageUseCase: Sendable {
    let videos: any VideoListRepository

    func callAsFunction(_ list: VideoList, cursor: String?) async throws -> FeedPage {
        try await videos.page(of: list, cursor: cursor)
    }
}

// Une liste de vidéos (grille, historique), source du lecteur vertical.
struct LoadVideoListUseCase: VideoPageSource {
    let videos: any VideoListRepository
    let list: VideoList

    func page(cursor: String?) async throws -> FeedPage {
        try await videos.page(of: list, cursor: cursor)
    }
}

struct RemoveFromHistoryUseCase: Sendable {
    let videos: any VideoListRepository

    func callAsFunction(videoID: String) async throws {
        try await videos.removeFromHistory(videoID: videoID)
    }
}

struct ClearHistoryUseCase: Sendable {
    let videos: any VideoListRepository

    func callAsFunction() async throws {
        try await videos.clearHistory()
    }
}

struct LoadCommentHistoryUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(cursor: String?) async throws -> CommentHistoryPage {
        try await interactions.myComments(cursor: cursor)
    }
}
