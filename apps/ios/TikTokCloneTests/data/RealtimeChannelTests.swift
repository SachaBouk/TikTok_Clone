import Foundation
import Synchronization
import Testing
@testable import TikTokClone

@Suite("WebSocketRealtimeChannel : authentification et reconnexion")
struct RealtimeChannelTests {
    let tokens = FakeTokens()

    func makeChannel(_ sockets: FakeSocketFactory, pauses: Pauses) -> WebSocketRealtimeChannel {
        WebSocketRealtimeChannel(
            url: URL(string: "ws://api.test/realtime")!,
            sockets: sockets,
            accessToken: { [tokens] in tokens.current },
            refreshToken: { [tokens] rejected in tokens.refresh(rejected) },
            pingInterval: .seconds(3600),
            pause: { pauses.record($0) }
        )
    }

    func collect(_ channel: WebSocketRealtimeChannel, count: Int) async -> [RealtimeUpdate] {
        var result: [RealtimeUpdate] = []
        for await update in channel.updates {
            result.append(update)
            if result.count == count { break }
        }
        return result
    }

    @Test("handshake 401 et fermeture 4001 : rafraîchissement puis reconnexion immédiate ; coupure : reconnexion après délai")
    func reconnects() async {
        let sockets = FakeSocketFactory([
            .refused(401),
            .accepted(messages: [processedJSON], closeCode: 4001),
            .accepted(messages: [], closeCode: 1006),
        ])
        let pauses = Pauses()
        let channel = makeChannel(sockets, pauses: pauses)
        await channel.connect()
        let updates = await collect(channel, count: 4)
        await channel.disconnect()

        #expect(updates.first == .connected)
        #expect(updates.count(where: { $0 == .connected }) == 3)
        #expect(updates.contains { if case .videoProcessed(let video) = $0 { video.id == "v1" } else { false } })
        #expect(sockets.tokens == ["t1", "t2", "t3", "t3"])
        #expect(tokens.refreshed == ["t1", "t2"])
        // Seule la coupure attend avant de se reconnecter.
        #expect(pauses.count == 1)
    }

    @Test("401 à nouveau après un rafraîchissement : attente avant de réessayer, pas de boucle")
    func noTightLoop() async {
        let sockets = FakeSocketFactory([.refused(401), .refused(401)])
        let pauses = Pauses()
        let channel = makeChannel(sockets, pauses: pauses)
        await channel.connect()
        _ = await collect(channel, count: 1)
        await channel.disconnect()

        #expect(sockets.tokens == ["t1", "t2", "t2"])
        #expect(tokens.refreshed == ["t1"])
        #expect(pauses.count == 1)
    }
}

private let processedJSON = """
{"event":"videoProcessed","data":{"id":"v1","userId":"u","description":null,"status":"ready",\
"hlsUrl":"http://cdn.test/v1/master.m3u8","thumbnailUrl":"http://cdn.test/v1/thumbnail.jpg","createdAt":"2026-09-25T12:00:00.123Z"}}
"""

// Attentes avant reconnexion, enregistrées sans attendre.
final class Pauses: Sendable {
    private let values = Mutex<[Duration]>([])

    var count: Int { values.withLock { $0.count } }
    func record(_ duration: Duration) { values.withLock { $0.append(duration) } }
}

// Tokens : t1, puis t2, t3… à chaque rafraîchissement.
final class FakeTokens: Sendable {
    private let state = Mutex((current: 1, refreshed: [String]()))

    var current: String { state.withLock { "t\($0.current)" } }
    var refreshed: [String] { state.withLock { $0.refreshed } }

    func refresh(_ rejected: String) -> String {
        state.withLock {
            $0.refreshed.append(rejected)
            $0.current += 1
            return "t\($0.current)"
        }
    }
}

final class FakeSocketFactory: WebSocketFactory {
    enum Script {
        case refused(Int)
        case accepted(messages: [String], closeCode: Int)
    }

    private let state: Mutex<(scripts: [Script], tokens: [String], sockets: [FakeSocket])>

    init(_ scripts: [Script]) {
        state = Mutex((scripts, [], []))
    }

    var tokens: [String] { state.withLock { $0.tokens } }
    // Messages envoyés par l'app, toutes connexions confondues.
    var sent: [String] { state.withLock { $0.sockets.flatMap(\.sent) } }

    // Une fois les scénarios épuisés : connexion acceptée qui reste ouverte.
    func connect(url: URL, accessToken: String) -> any WebSocketConnection {
        let script = state.withLock { state in
            state.tokens.append(accessToken)
            return state.scripts.isEmpty ? nil : state.scripts.removeFirst()
        }
        let socket = FakeSocket(script)
        state.withLock { $0.sockets.append(socket) }
        return socket
    }
}

final class FakeSocket: WebSocketConnection {
    private let script: FakeSocketFactory.Script?
    private let state: Mutex<(messages: [String], closeCode: Int, sent: [String])>

    init(_ script: FakeSocketFactory.Script?) {
        self.script = script
        if case .accepted(let messages, _) = script {
            state = Mutex((messages, 0, []))
        } else {
            state = Mutex(([], 0, []))
        }
    }

    var sent: [String] { state.withLock { $0.sent } }

    func send(_ text: String) async throws {
        state.withLock { $0.sent.append(text) }
    }

    func ping() async throws {
        if case .refused = script { throw URLError(.badServerResponse) }
    }

    func receive() async throws -> String? {
        guard case .accepted(_, let code) = script else {
            // Reste ouverte jusqu'à la déconnexion.
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
        return try state.withLock { state in
            guard !state.messages.isEmpty else {
                state.closeCode = code
                throw URLError(.networkConnectionLost)
            }
            return state.messages.removeFirst()
        }
    }

    func close() {}

    var closeCode: Int { state.withLock { $0.closeCode } }

    var handshakeStatus: Int? {
        if case .refused(let status) = script { status } else { nil }
    }
}
