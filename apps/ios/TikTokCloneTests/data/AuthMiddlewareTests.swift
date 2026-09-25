import Foundation
import Synchronization
import Testing
import TikTokAPI
@testable import TikTokClone

@Suite("AuthMiddleware et TokenRefresher")
struct AuthMiddlewareTests {
    let store = InMemoryTokenStore(.valid("A1", refresh: "R1"))
    let log = RequestLog()
    let refreshes = Counter()
    let expirations = Counter()

    // Client dont le transport accepte seulement `acceptedToken`, et dont le refresh renvoie `outcome`.
    func makeClient(
        acceptedToken: String = "A1",
        refreshDelay: Duration = .zero,
        outcome: @escaping @Sendable () throws -> TokenRefresher.Outcome = { .refreshed(.valid("A2", refresh: "R2")) }
    ) -> Client {
        let refresher = TokenRefresher(
            store: store,
            refresh: { [refreshes] _ in
                refreshes.increment()
                try await Task.sleep(for: refreshDelay)
                return try outcome()
            },
            onSessionExpired: { [expirations] in expirations.increment() }
        )
        let transport = MockTransport { [log] request, operationID in
            log.record(request, operationID)
            if operationID == "login" { return json(.ok, tokensJSON(access: "L1", refresh: "LR1")) }
            return request.headerFields[.authorization] == "Bearer \(acceptedToken)"
                ? json(.ok, profileJSON)
                : json(.unauthorized, errorJSON(401, "Unauthorized"))
        }
        return TikTokCloneTests.makeClient(transport: transport, middlewares: [AuthMiddleware(refresher: refresher)])
    }

    @Test("ajoute l'access token enregistré")
    func addsBearer() async throws {
        _ = try await makeClient().getMyProfile().ok
        #expect(log.authorizations == ["Bearer A1"])
    }

    @Test("sans session, la requête part sans token")
    func noSession() async throws {
        store.clear()
        _ = try await makeClient().getMyProfile()
        #expect(log.authorizations == [nil])
    }

    @Test("sur un 401 : rafraîchit, enregistre la nouvelle paire et rejoue la requête")
    func refreshOnUnauthorized() async throws {
        let profile = try await makeClient(acceptedToken: "A2").getMyProfile().ok.body.json
        #expect(profile.username == "alice")
        #expect(log.authorizations == ["Bearer A1", "Bearer A2"])
        #expect(refreshes.count == 1)
        #expect(store.load()?.refreshToken == "R2")
    }

    @Test("des 401 simultanés ne déclenchent qu'un seul rafraîchissement")
    func singleFlight() async throws {
        let client = makeClient(acceptedToken: "A2", refreshDelay: .milliseconds(100))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try await client.getMyProfile().ok }
            }
            try await group.waitForAll()
        }
        #expect(refreshes.count == 1)
    }

    @Test("refresh token refusé : session effacée, app prévenue, 401 rendu")
    func refreshRejected() async throws {
        let output = try await makeClient(acceptedToken: "A2", outcome: { .rejected }).getMyProfile()
        guard case .unauthorized = output else { Issue.record("attendu .unauthorized, reçu \(output)"); return }
        #expect(store.load() == nil)
        #expect(expirations.count == 1)
    }

    @Test("API injoignable au rafraîchissement : la session est gardée")
    func refreshOffline() async throws {
        let output = try await makeClient(acceptedToken: "A2", outcome: { throw URLError(.notConnectedToInternet) }).getMyProfile()
        guard case .unauthorized = output else { Issue.record("attendu .unauthorized"); return }
        #expect(store.load()?.refreshToken == "R1")
        #expect(expirations.count == 0)
    }

    @Test("token expiré : rafraîchi avant l'envoi (une route publique ne répondrait pas 401)")
    func proactiveRefresh() async throws {
        try store.save(.expired("A1", refresh: "R1"))
        _ = try await makeClient(acceptedToken: "A2").getMyProfile().ok
        #expect(log.authorizations == ["Bearer A2"])
        #expect(refreshes.count == 1)
    }

    @Test("les routes d'authentification partent sans token")
    func authRoutesUnauthenticated() async throws {
        _ = try await makeClient().login(body: .json(.init(email: "a@b.c", password: "motdepasse"))).ok
        #expect(log.authorizations == [nil])
    }
}
