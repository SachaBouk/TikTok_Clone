import Foundation

// Connexion temps réel à l'API (ADR-011) : WebSocket `/realtime`, access token dans l'en-tête du handshake.
// - Handshake refusé (HTTP 401) ou fermeture 4001 (access token expiré) : la paire de tokens est rafraîchie,
//   puis l'app se reconnecte aussitôt (une fois ; ensuite avec délai).
// - Coupure, fermeture 1001 (arrêt d'une instance), ping sans réponse : reconnexion avec un délai croissant.
// - L'app envoie ses propres pings pour détecter une connexion morte de son côté.
// - À chaque connexion, `.connected` : rien n'est rejoué, les écrans relisent l'état par l'API REST.
// - L'app n'envoie qu'un message, « en train d'écrire », sur la connexion établie (perdu sinon).
actor WebSocketRealtimeChannel: RealtimeChannel {
    static let tokenExpiredCloseCode = 4001

    nonisolated let updates: AsyncStream<RealtimeUpdate>
    private let continuation: AsyncStream<RealtimeUpdate>.Continuation
    private let url: URL
    private let sockets: any WebSocketFactory
    // Access token valide (rafraîchi s'il est expiré) ; nil sans session utilisable.
    private let accessToken: @Sendable () async -> String?
    // Après un refus : nouvel access token, ou nil (session terminée, API injoignable).
    private let refreshToken: @Sendable (_ rejected: String) async -> String?
    private let policy: ReconnectPolicy
    private let pingInterval: Duration
    private let pingTimeout: Duration
    // Attente avant une reconnexion (remplacée dans les tests).
    private let pause: @Sendable (Duration) async throws -> Void
    private var loop: Task<Void, Never>?
    // Connexion établie en cours, pour les messages de l'app.
    private var current: (any WebSocketConnection)?

    init(
        url: URL,
        sockets: any WebSocketFactory,
        accessToken: @escaping @Sendable () async -> String?,
        refreshToken: @escaping @Sendable (_ rejected: String) async -> String?,
        policy: ReconnectPolicy = ReconnectPolicy(),
        pingInterval: Duration = .seconds(25),
        pingTimeout: Duration = .seconds(10),
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(100))
        self.url = url
        self.sockets = sockets
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.policy = policy
        self.pingInterval = pingInterval
        self.pingTimeout = pingTimeout
        self.pause = pause
    }

    func connect() {
        guard loop == nil else { return }
        loop = Task { await self.run() }
    }

    func disconnect() {
        loop?.cancel()
        loop = nil
        current = nil
    }

    func sendTyping(conversationID: String) async {
        guard let current, let text = RealtimeClientMessageEncoder.typing(conversationID: conversationID) else { return }
        // Au mieux : une connexion qui vient de tomber sera détectée par la boucle de réception.
        try? await current.send(text)
    }

    private func run() async {
        var failures = 0
        var refreshedSinceLastConnection = false
        while !Task.isCancelled {
            guard let token = await accessToken() else {
                failures += 1
                if await wait(failures) { continue } else { return }
            }
            let socket = sockets.connect(url: url, accessToken: token)
            if await serve(socket) {
                failures = 0
                refreshedSinceLastConnection = false
            }
            if Task.isCancelled { return }

            let rejected = socket.handshakeStatus == 401 || socket.closeCode == Self.tokenExpiredCloseCode
            if rejected, !refreshedSinceLastConnection {
                refreshedSinceLastConnection = true
                if await refreshToken(token) != nil { continue }
            }
            failures += 1
            if !(await wait(failures)) { return }
        }
    }

    // Faux si la tâche a été annulée pendant l'attente (déconnexion).
    private func wait(_ attempt: Int) async -> Bool {
        do {
            try await pause(policy.delay(attempt: attempt, jitter: Double.random(in: -1...1)))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    // Tant que la connexion vit : reçoit les messages et envoie les pings. Vrai si elle a été établie.
    private func serve(_ socket: any WebSocketConnection) async -> Bool {
        do {
            try await withTimeout(pingTimeout) { try await socket.ping() }
        } catch {
            socket.close()
            return false
        }
        current = socket
        continuation.yield(.connected)
        defer { if current === socket { current = nil } }

        await withTaskGroup(of: Void.self) { [continuation, pingInterval, pingTimeout] group in
            group.addTask {
                let decoder = RealtimeEventDecoder()
                do {
                    while true {
                        if let text = try await socket.receive(), let update = decoder.decode(text) { continuation.yield(update) }
                    }
                } catch {
                    // Connexion fermée.
                }
            }
            group.addTask {
                while (try? await Task.sleep(for: pingInterval)) != nil {
                    guard (try? await withTimeout(pingTimeout, { try await socket.ping() })) != nil else { return }
                }
            }
            // La première tâche terminée (connexion fermée, ping sans réponse, déconnexion) arrête l'autre.
            await group.next()
            group.cancelAll()
        }
        socket.close()
        return true
    }
}

// Délai avant chaque reconnexion : 1, 2, 4… jusqu'à 30 s, à ±20 % près pour ne pas reconnecter tous les appareils
// au même instant après l'arrêt d'une instance.
struct ReconnectPolicy: Sendable {
    var base: Duration = .seconds(1)
    var maximum: Duration = .seconds(30)
    var jitterRatio = 0.2

    // `attempt` à partir de 1 ; `jitter` entre -1 et 1.
    func delay(attempt: Int, jitter: Double) -> Duration {
        let exponent = min(max(attempt - 1, 0), 16)
        let raw = min(base * (1 << exponent), maximum)
        return raw * (1 + jitterRatio * min(max(jitter, -1), 1))
    }
}

struct TimeoutError: Error {}

func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimeoutError() }
        return result
    }
}
