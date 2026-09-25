import Foundation
import Testing
import TikTokAPI
@testable import TikTokClone

@Suite("RemoteAuthRepository et RemoteProfileRepository")
struct RemoteAuthRepositoryTests {
    let store = InMemoryTokenStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let log = RequestLog()

    func repository(_ respond: @escaping @Sendable (String) throws -> (HTTPResponse, HTTPBody?)) -> RemoteAuthRepository {
        let client = makeClient(transport: MockTransport { [log] request, operationID in
            log.record(request, operationID)
            return try respond(operationID)
        })
        return RemoteAuthRepository(client: client, store: store, now: { [now] in now })
    }

    @Test("connexion : enregistre la paire de tokens et son expiration")
    func loginSavesTokens() async throws {
        try await repository { _ in json(.ok, tokensJSON(access: "A1", refresh: "R1")) }.login(email: "a@b.c", password: "motdepasse")
        #expect(store.load() == AuthTokens(accessToken: "A1", refreshToken: "R1", accessTokenExpiresAt: now.addingTimeInterval(900)))
    }

    @Test("connexion refusée : invalidCredentials, rien d'enregistré")
    func loginRejected() async {
        await #expect(throws: AuthError.invalidCredentials) {
            try await repository { _ in json(.unauthorized, errorJSON(401, "Email ou mot de passe incorrect")) }.login(email: "a@b.c", password: "x")
        }
        #expect(store.load() == nil)
    }

    @Test("inscription refusée : message de l'API (pseudo pris)")
    func registerConflict() async {
        await #expect(throws: AuthError.rejected("Le pseudo @alice est déjà pris")) {
            try await repository { _ in json(.conflict, errorJSON(409, "Le pseudo @alice est déjà pris")) }
                .register(Registration(email: "a@b.c", password: "motdepasse", username: "alice", displayName: "Alice"))
        }
    }

    @Test("erreurs de validation : messages réunis")
    func validationMessages() async {
        let body = #"{"statusCode":400,"message":["email must be an email","password too short"]}"#
        await #expect(throws: AuthError.rejected("email must be an email\npassword too short")) {
            try await repository { _ in json(.badRequest, body) }.login(email: "x", password: "y")
        }
    }

    @Test("API injoignable : network")
    func network() async {
        await #expect(throws: AuthError.network) {
            try await repository { _ in throw URLError(.cannotConnectToHost) }.login(email: "a@b.c", password: "motdepasse")
        }
    }

    @Test("déconnexion : session oubliée localement et révoquée, même si le serveur échoue")
    func logout() async throws {
        try store.save(.valid("A1", refresh: "R1"))
        await repository { _ in throw URLError(.notConnectedToInternet) }.logout()
        #expect(store.load() == nil)
        #expect(log.operations == ["logout"])
    }

    @Test("profil : mapping du DTO, dates avec millisecondes")
    func profileMapping() async throws {
        let client = makeClient(transport: MockTransport { _, _ in json(.ok, profileJSON) })
        let profile = try await RemoteProfileRepository(client: client).myProfile()
        #expect(profile.username == "alice")
        #expect(profile.avatarURL == nil)
        #expect(profile.followersCount == 3)
        #expect(profile.createdAt == ISO8601DateFormatter.fractional.date(from: "2026-01-01T12:00:00.123Z"))
    }

    @Test("profil : 401 ou compte supprimé → sessionExpired")
    func profileExpired() async {
        for status in [HTTPResponse.Status.unauthorized, .notFound] {
            let client = makeClient(transport: MockTransport { _, _ in json(status, errorJSON(status.code, "x")) })
            await #expect(throws: AuthError.sessionExpired) { try await RemoteProfileRepository(client: client).myProfile() }
        }
    }
}

extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
