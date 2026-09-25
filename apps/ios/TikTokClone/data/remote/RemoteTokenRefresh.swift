import Foundation
import TikTokAPI

// `POST /auth/refresh`, avec un client sans AuthMiddleware (sinon le rafraîchissement se rappellerait).
enum RemoteTokenRefresh {
    static func make(client: Client, now: @escaping @Sendable () -> Date = { Date() }) -> @Sendable (String) async throws -> TokenRefresher.Outcome {
        { refreshToken in
            switch try await client.refresh(body: .json(.init(refreshToken: refreshToken))) {
            case .ok(let ok):
                return .refreshed(AuthTokens(try ok.body.json, receivedAt: now()))
            case .unauthorized, .badRequest:
                return .rejected
            case .undocumented(let statusCode, _):
                // 5xx : le serveur ne répond pas normalement ; la session est gardée.
                throw URLError(.badServerResponse, userInfo: ["statusCode": statusCode])
            }
        }
    }
}

extension AuthTokens {
    init(_ response: Components.Schemas.AuthTokensResponse, receivedAt: Date) {
        self.init(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            accessTokenExpiresAt: receivedAt.addingTimeInterval(TimeInterval(response.accessTokenExpiresIn))
        )
    }
}
