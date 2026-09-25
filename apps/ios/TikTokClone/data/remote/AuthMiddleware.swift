import Foundation
import TikTokAPI

// Ajoute l'access token à chaque requête et gère son renouvellement (ADR-010) :
// - avant l'envoi, un token expiré est rafraîchi. Indispensable : sur une route publique (feed, profils),
//   l'API traite un token expiré comme une absence de compte, sans 401 ; les boutons seraient faux ;
// - sur un 401, le token est rafraîchi puis la requête rejouée une fois.
// Les routes d'authentification elles-mêmes passent sans token.
struct AuthMiddleware: ClientMiddleware {
    static let unauthenticatedOperations: Set<String> = ["login", "register", "refresh", "logout", "loginWithApple"]

    let refresher: TokenRefresher

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard !Self.unauthenticatedOperations.contains(operationID),
              let token = await refresher.validAccessToken() else {
            return try await next(request, body, baseURL)
        }

        let response = try await next(authorized(request, token), body, baseURL)
        // Un corps à lecture unique ne peut pas être renvoyé : la réponse 401 est alors rendue telle quelle.
        guard response.0.status == .unauthorized, body?.iterationBehavior != .single,
              let refreshed = await refresher.refreshTokens(replacing: token) else {
            return response
        }
        return try await next(authorized(request, refreshed.accessToken), body, baseURL)
    }

    private func authorized(_ request: HTTPRequest, _ token: String) -> HTTPRequest {
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"
        return request
    }
}
