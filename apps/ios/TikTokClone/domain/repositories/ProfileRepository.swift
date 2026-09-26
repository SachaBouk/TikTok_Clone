import Foundation

// Port des profils (module users).
protocol ProfileRepository: Sendable {
    // Lève AppError.sessionExpired si la session n'est plus valide (ou le compte supprimé).
    func myProfile() async throws -> UserProfile
    // Profil public ; `.notFound` si le compte n'existe pas.
    func profile(username: String) async throws -> UserProfile
    // `.rejected` : pseudo pris, valeur refusée.
    func updateMyProfile(_ changes: ProfileChanges) async throws -> UserProfile
    func createAvatarUpload(type: AvatarImageType, size: Int) async throws -> AvatarUpload
    // Installe la photo envoyée ; `.rejected` si le fichier est absent ou n'est pas une vraie image.
    func setAvatar(id: String) async throws -> UserProfile
    func removeAvatar() async throws -> UserProfile
    // Définitif : vidéos, messages, abonnés… disparaissent.
    func deleteAccount() async throws
}

// Envoi de la photo de profil au stockage, sur son URL signée (Content-Type et taille signés).
protocol AvatarUploadTransport: Sendable {
    func upload(_ data: Data, type: AvatarImageType, to url: URL) async throws
}

// Port des relations entre comptes (module interactions) : relation, abonnés, abonnements, blocage.
protocol RelationshipRepository: Sendable {
    func relationship(username: String) async throws -> Relationship
    func follows(_ kind: FollowListKind, username: String, cursor: String?) async throws -> FollowPage
    // Idempotent. Bloquer supprime les follows dans les deux sens.
    func setBlocked(_ blocked: Bool, username: String) async throws
    func blockedUsers() async throws -> [UserSummary]
}

// Port des listes de vidéos au format du feed (module feed) et de l'historique de visionnage.
protocol VideoListRepository: Sendable {
    func page(of list: VideoList, cursor: String?) async throws -> FeedPage
    func removeFromHistory(videoID: String) async throws
    func clearHistory() async throws
}
