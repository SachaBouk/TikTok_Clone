import Foundation

// Rafraîchissement de la session (ADR-010 : refresh token à usage unique, rotation à chaque appel).
// Un seul rafraîchissement à la fois : des requêtes simultanées qui trouvent le token expiré (ou reçoivent
// un 401) attendent le même résultat. Rejouer un refresh token déjà utilisé révoquerait toute la session.
actor TokenRefresher {
    enum Outcome: Sendable {
        case refreshed(AuthTokens)
        // Refresh token refusé (expiré, révoqué, compte supprimé) : la session est terminée.
        case rejected
    }

    private let store: any TokenStore
    // Appel à `POST /auth/refresh`. Lève une erreur si l'API est injoignable.
    private let refresh: @Sendable (_ refreshToken: String) async throws -> Outcome
    // Prévenu quand la session se termine (l'app repasse en invité).
    private let onSessionExpired: @Sendable () async -> Void
    private let now: @Sendable () -> Date
    private var inFlight: Task<AuthTokens?, Never>?

    init(
        store: any TokenStore,
        refresh: @escaping @Sendable (_ refreshToken: String) async throws -> Outcome,
        onSessionExpired: @escaping @Sendable () async -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.refresh = refresh
        self.onSessionExpired = onSessionExpired
        self.now = now
    }

    // Access token à envoyer : celui enregistré, rafraîchi d'abord s'il est expiré. Nil sans session,
    // ou si le rafraîchissement a échoué (la requête part alors sans token, en mode invité).
    func validAccessToken() async -> String? {
        guard let tokens = store.load() else { return nil }
        if !tokens.isAccessTokenExpired(at: now()) { return tokens.accessToken }
        return await refreshTokens(replacing: tokens.accessToken)?.accessToken
    }

    // Après un 401 avec `rejected` : un nouvel access token, ou nil si la session est terminée
    // ou l'API injoignable. Si un autre appel a déjà rafraîchi entre-temps, renvoie simplement le nouveau.
    func refreshTokens(replacing rejected: String) async -> AuthTokens? {
        if let inFlight { return await inFlight.value }
        guard let tokens = store.load() else { return nil }
        if tokens.accessToken != rejected, !tokens.isAccessTokenExpired(at: now()) { return tokens }

        let task = Task { await self.perform(using: tokens.refreshToken) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func perform(using refreshToken: String) async -> AuthTokens? {
        do {
            switch try await refresh(refreshToken) {
            case .refreshed(let tokens):
                try store.save(tokens)
                return tokens
            case .rejected:
                store.clear()
                await onSessionExpired()
                return nil
            }
        } catch {
            // Réseau ou Keychain : la session est gardée, un prochain appel réessaiera.
            return nil
        }
    }
}
