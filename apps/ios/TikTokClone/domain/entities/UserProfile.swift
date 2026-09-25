import Foundation

// Profil d'un compte (ADR-016 : nom, pseudo, photo, bio, abonnés, abonnements).
// Entité du domaine : ne dépend ni du client généré ni de l'API (ADR-002).
struct UserProfile: Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    let bio: String?
    let followersCount: Int
    let followingCount: Int
    let createdAt: Date
}
