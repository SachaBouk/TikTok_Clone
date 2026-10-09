import Foundation
import Synchronization

@testable import TikTokClone

// API du live en mémoire (ADR-053) : connexions et lives choisis par le test, appels notés.
final class FakeLiveRepository: LiveRepository {
    struct State {
        var connection: LiveConnection?
        var lives: [String: LiveStream] = [:]
        var following: [LiveStream] = []
        var userLives: [String: LiveStream] = [:]
        var startError: AppError?
        var joinError: AppError?
        var messageError: AppError?
        var heartsTotal = 0
        var calls: [String] = []
        var titles: [String?] = []
        var messages: [String] = []
        var deleted: [String] = []
        var hearts: [Int] = []
        var ended: [String] = []
    }

    let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    var hearts: [Int] { state.withLock { $0.hearts } }
    var ended: [String] { state.withLock { $0.ended } }

    func start(title: String?) async throws -> LiveConnection {
        try state.withLock { state in
            state.calls.append("start")
            state.titles.append(title)
            if let error = state.startError { throw error }
            guard let connection = state.connection else { throw AppError.unexpected }
            return connection
        }
    }

    func join(liveID: String) async throws -> LiveConnection {
        try state.withLock { state in
            state.calls.append("join:\(liveID)")
            if let error = state.joinError { throw error }
            guard let connection = state.connection else { throw AppError.unexpected }
            return connection
        }
    }

    func live(id: String) async throws -> LiveStream {
        try state.withLock { state in
            state.calls.append("live:\(id)")
            guard let live = state.lives[id] else { throw AppError.notFound }
            return live
        }
    }

    func end(liveID: String) async throws -> LiveStream {
        try state.withLock { state in
            state.ended.append(liveID)
            guard let live = state.lives[liveID] else { throw AppError.notFound }
            return live
        }
    }

    func sendMessage(liveID: String, content: String) async throws -> LiveChatMessage {
        try state.withLock { state in
            if let error = state.messageError { throw error }
            state.messages.append(content)
            return LiveChatMessage(
                id: "m\(state.messages.count)", liveID: liveID, user: .alice, content: content, createdAt: Date(timeIntervalSince1970: 0))
        }
    }

    func deleteMessage(liveID: String, messageID: String) async throws {
        state.withLock { $0.deleted.append(messageID) }
    }

    func sendHearts(liveID: String, count: Int) async throws -> Int {
        state.withLock { state in
            state.hearts.append(count)
            state.heartsTotal += count
            return state.heartsTotal
        }
    }

    func followingLives() async throws -> [LiveStream] {
        state.withLock { $0.following }
    }

    func userLive(username: String) async throws -> LiveStream? {
        state.withLock { $0.userLives[username] }
    }
}

// Salle en mémoire : connexion réussie ou non, mises à jour envoyées par le test.
@MainActor
final class FakeLiveRoom: LiveRoom {
    let updates: AsyncStream<LiveRoomUpdate>
    private let continuation: AsyncStream<LiveRoomUpdate>.Continuation
    var connectError: LiveRoomError?
    private(set) var connected: [(token: String, publish: Bool)] = []
    private(set) var disconnects = 0
    private(set) var cameraSwitches = 0

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func connect(url: URL, token: String, publish: Bool) async throws {
        if let connectError { throw connectError }
        connected.append((token, publish))
    }

    func switchCamera() async {
        cameraSwitches += 1
    }

    func disconnect() async {
        disconnects += 1
    }

    func emit(_ update: LiveRoomUpdate) {
        continuation.yield(update)
    }
}

extension LiveStream {
    static func sample(
        _ id: String = "live-1", host: UserSummary = .bob, status: LiveStatus = .live, endReason: LiveEndReason? = nil, stats: LiveStats? = nil
    )
        -> LiveStream
    {
        LiveStream(
            id: id, host: host, title: "Mon live", status: status, startedAt: Date(timeIntervalSince1970: 0),
            endedAt: status == .ended ? Date(timeIntervalSince1970: 600) : nil, endReason: endReason, stats: stats)
    }
}

extension LiveConnection {
    static func sample(_ live: LiveStream = .sample(), role: LiveRole = .viewer, messages: [LiveChatMessage] = []) -> LiveConnection {
        LiveConnection(live: live, role: role, url: URL(string: "ws://localhost:7880")!, token: "jeton", recentMessages: messages)
    }
}

extension LiveChatMessage {
    static func sample(_ id: String, by user: UserSummary = .bob, content: String = "Salut") -> LiveChatMessage {
        LiveChatMessage(id: id, liveID: "live-1", user: user, content: content, createdAt: Date(timeIntervalSince1970: 0))
    }
}
