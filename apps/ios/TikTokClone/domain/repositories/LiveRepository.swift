import Foundation

// Live (ADR-053) par l'API (module live). Lève AppError.notFound (live inconnu ou masqué), .rejected (live terminé,
// texte invalide), .tooManyActions, .sessionExpired.
protocol LiveRepository: Sendable {
    // Lance un live (ou reprend celui en cours) : jeton pour publier.
    func start(title: String?) async throws -> LiveConnection
    // Rejoindre : jeton pour regarder (pour publier, si c'est le sien), derniers messages.
    func join(liveID: String) async throws -> LiveConnection
    func live(id: String) async throws -> LiveStream
    // Fin par l'auteur : le live terminé, avec ses chiffres.
    func end(liveID: String) async throws -> LiveStream
    func sendMessage(liveID: String, content: String) async throws -> LiveChatMessage
    func deleteMessage(liveID: String, messageID: String) async throws
    // Renvoie le total des cœurs du live.
    func sendHearts(liveID: String, count: Int) async throws -> Int
    // Lives en cours des comptes suivis (rangée).
    func followingLives() async throws -> [LiveStream]
    // Live en cours d'un compte (anneau du profil) ; nil s'il n'en a pas.
    func userLive(username: String) async throws -> LiveStream?
}
