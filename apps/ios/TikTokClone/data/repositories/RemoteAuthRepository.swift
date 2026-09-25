import Foundation
import TikTokAPI

// Authentification par l'API (ADR-010) ; tokens enregistrés dans le TokenStore (Keychain).
struct RemoteAuthRepository: AuthRepository {
    let client: Client
    let store: any TokenStore
    var now: @Sendable () -> Date = { Date() }

    func login(email: String, password: String) async throws {
        let output = try await mappingErrors { try await client.login(body: .json(.init(email: email, password: password))) }
        switch output {
        case .ok(let ok): try save(try ok.body.json)
        case .unauthorized: throw AppError.invalidCredentials
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func register(_ registration: Registration) async throws {
        let body = Components.Schemas.RegisterRequest(
            email: registration.email,
            password: registration.password,
            username: registration.username,
            displayName: registration.displayName
        )
        let output = try await mappingErrors { try await client.register(body: .json(body)) }
        switch output {
        case .created(let created): try save(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func logout() async {
        guard let tokens = store.load() else { return }
        store.clear()
        // Révocation côté serveur au mieux : hors ligne, la session expirera d'elle-même (30 jours).
        _ = try? await client.logout(body: .json(.init(refreshToken: tokens.refreshToken)))
    }

    func hasStoredSession() -> Bool {
        store.load() != nil
    }

    private func save(_ response: Components.Schemas.AuthTokensResponse) throws {
        do {
            try store.save(AuthTokens(response, receivedAt: now()))
        } catch {
            throw AppError.unexpected
        }
    }
}
