import Foundation
import TikTokAPI

// Authentification par l'API (ADR-010) ; tokens enregistrés dans le TokenStore (Keychain).
struct RemoteAuthRepository: AuthRepository {
    let client: Client
    let store: any TokenStore
    var now: @Sendable () -> Date = { Date() }

    // Email ou pseudo (ADR-055).
    func login(identifier: String, password: String) async throws {
        let output = try await mappingErrors { try await client.login(body: .json(.init(identifier: identifier, password: password))) }
        switch output {
        case .ok(let ok): try save(try ok.body.json)
        case .unauthorized: throw AppError.invalidCredentials
        case .forbidden: throw AppError.accountSuspended
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let error): throw AppError.tooManyLoginAttempts(retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .undocumented: throw AppError.unexpected
        }
    }

    func register(_ registration: Registration) async throws {
        let body = Components.Schemas.RegisterRequest(
            email: registration.email,
            password: registration.password,
            username: registration.username,
            displayName: registration.displayName,
            birthDate: registration.birthDate.isoString
        )
        let output = try await mappingErrors { try await client.register(body: .json(body)) }
        switch output {
        case .created(let created): try save(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .conflict(let error): throw AppError.alreadyRegistered(try error.body.json.text)
        case .tooManyRequests(let error): throw AppError.tooManyActions(.signup, retryAfter: max(1, error.headers.retryAfter ?? 60))
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
