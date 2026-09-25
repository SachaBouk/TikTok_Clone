import Foundation

// Tokens d'une session (ADR-010) : access token JWT de 15 min, refresh token opaque à usage unique.
struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date

    // Marge avant l'expiration : un token presque expiré est rafraîchi avant d'être envoyé.
    static let expiryMargin: TimeInterval = 30

    func isAccessTokenExpired(at now: Date) -> Bool {
        now >= accessTokenExpiresAt.addingTimeInterval(-Self.expiryMargin)
    }
}

// Source locale des tokens (couche data/, ADR-002). Keychain dans l'app, en mémoire dans les tests.
protocol TokenStore: Sendable {
    func load() -> AuthTokens?
    func save(_ tokens: AuthTokens) throws
    func clear()
}
