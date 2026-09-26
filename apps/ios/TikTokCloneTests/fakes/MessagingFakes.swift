import Foundation
import Synchronization
@testable import TikTokClone

// Messagerie en mémoire : conversations et messages (du plus ancien au plus récent), 2 par page.
// Le compte connecté est Alice (`UserProfile.alice`).
final class FakeMessagingRepository: MessagingRepository {
    struct State {
        var conversations: [String: Conversation] = [:]
        var messages: [String: [DirectMessage]] = [:]
        var badges = MessagingBadges.zero
        var calls: [String] = []
        var sent: [(conversationID: String, content: String?, videoID: String?)] = []
        var markedUpTo: [String?] = []
        var error: AppError?
        var sendError: AppError?
        // Identifiants « n101 »… : après les « mNN » des tests (ordre des UUID v7).
        var nextID = 100
    }

    let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    var markedUpTo: [String?] { state.withLock { $0.markedUpTo } }
    var sentContents: [String?] { state.withLock { $0.sent.map(\.content) } }
    var sentVideoIDs: [String?] { state.withLock { $0.sent.map(\.videoID) } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }
    func failSending(with error: AppError?) { state.withLock { $0.sendError = error } }
    func setBadges(_ badges: MessagingBadges) { state.withLock { $0.badges = badges } }

    func add(_ conversation: Conversation, messages: [DirectMessage] = []) {
        state.withLock {
            $0.conversations[conversation.id] = conversation
            $0.messages[conversation.id] = messages
        }
    }

    func update(_ id: String, _ change: (inout Conversation) -> Void) {
        state.withLock { state in
            guard var conversation = state.conversations[id] else { return }
            change(&conversation)
            state.conversations[id] = conversation
        }
    }

    func messages(of conversationID: String) -> [DirectMessage] {
        state.withLock { $0.messages[conversationID] ?? [] }
    }

    func conversations(cursor: String?) async throws -> ConversationPage {
        try page(cursor: cursor, call: "conversations") { $0.status != .requestReceived }
    }

    func requests(cursor: String?) async throws -> ConversationPage {
        try page(cursor: cursor, call: "requests") { $0.status == .requestReceived }
    }

    func open(username: String) async throws -> Conversation {
        try state.withLock { state in
            state.calls.append("open:\(username)")
            if let error = state.error { throw error }
            if let existing = state.conversations.values.first(where: { $0.participant.username == username }) { return existing }
            let conversation = Conversation.sample("c-\(username)", with: UserSummary(id: "\(username)-id", username: username, displayName: username.capitalized, avatarURL: nil))
            state.conversations[conversation.id] = conversation
            state.messages[conversation.id] = []
            return conversation
        }
    }

    func conversation(id: String) async throws -> Conversation {
        try state.withLock { state in
            state.calls.append("conversation:\(id)")
            if let error = state.error { throw error }
            guard let conversation = state.conversations[id] else { throw AppError.notFound }
            return conversation
        }
    }

    func badges() async throws -> MessagingBadges {
        try state.withLock { state in
            if let error = state.error { throw error }
            return state.badges
        }
    }

    func messages(conversationID: String, cursor: String?) async throws -> MessagePage {
        try state.withLock { state in
            state.calls.append("messages:\(cursor ?? "-")")
            if let error = state.error { throw error }
            let all = Array((state.messages[conversationID] ?? []).reversed())
            let start = cursor.flatMap { c in all.firstIndex { $0.id == c }.map { $0 + 1 } } ?? 0
            let page = Array(all.dropFirst(start).prefix(2))
            return MessagePage(messages: page, nextCursor: start + 2 < all.count ? page.last?.id : nil)
        }
    }

    func send(conversationID: String, content: String?, videoID: String?) async throws -> DirectMessage {
        try state.withLock { state in
            state.sent.append((conversationID, content, videoID))
            if let error = state.sendError ?? state.error { throw error }
            state.nextID += 1
            let message = DirectMessage.sample("n\(state.nextID)", in: conversationID, from: UserProfile.alice.id, content: content ?? "",
                                               sharedVideoID: videoID)
            state.messages[conversationID, default: []].append(message)
            if var conversation = state.conversations[conversationID] {
                conversation.lastMessage = message
                state.conversations[conversationID] = conversation
            }
            return message
        }
    }

    func markRead(conversationID: String, upToID: String?) async throws -> MessagingBadges {
        try state.withLock { state in
            state.markedUpTo.append(upToID)
            if let error = state.error { throw error }
            state.conversations[conversationID]?.unreadCount = 0
            state.badges.unreadConversations = max(0, state.badges.unreadConversations - 1)
            return state.badges
        }
    }

    func accept(conversationID: String) async throws -> Conversation {
        try state.withLock { state in
            state.calls.append("accept")
            if let error = state.error { throw error }
            guard var conversation = state.conversations[conversationID] else { throw AppError.notFound }
            conversation.status = .direct
            state.conversations[conversationID] = conversation
            return conversation
        }
    }

    func decline(conversationID: String) async throws {
        try state.withLock { state in
            state.calls.append("decline")
            if let error = state.error { throw error }
            state.conversations[conversationID] = nil
        }
    }

    func deleteConversation(id: String) async throws {
        try state.withLock { state in
            state.calls.append("deleteConversation")
            if let error = state.error { throw error }
            state.conversations[id] = nil
        }
    }

    func deleteMessage(id: String) async throws {
        try state.withLock { state in
            state.calls.append("deleteMessage:\(id)")
            if let error = state.error { throw error }
            for key in state.messages.keys { state.messages[key]?.removeAll { $0.id == id } }
        }
    }

    // Conversations triées par dernier message, du plus récent au plus ancien, sans les vides.
    private func page(cursor: String?, call: String, _ include: (Conversation) -> Bool) throws -> ConversationPage {
        try state.withLock { state in
            state.calls.append(call)
            if let error = state.error { throw error }
            let all = state.conversations.values
                .filter { $0.lastMessage != nil && include($0) }
                .sorted { !MessageRules.isAtOrBefore($0.lastMessage!.id, $1.lastMessage!.id) }
            let start = cursor.flatMap { c in all.firstIndex { $0.lastMessage?.id == c }.map { $0 + 1 } } ?? 0
            let page = Array(all.dropFirst(start).prefix(2))
            return ConversationPage(conversations: page, nextCursor: start + 2 < all.count ? page.last?.lastMessage?.id : nil)
        }
    }
}

// Connexion temps réel simulée : enregistre les « en train d'écrire » envoyés.
final class FakeRealtimeChannel: RealtimeChannel {
    let updates: AsyncStream<RealtimeUpdate>
    private let typing = Mutex<[String]>([])

    init() {
        updates = AsyncStream { _ in }
    }

    var typingSent: [String] { typing.withLock { $0 } }
    func connect() async {}
    func disconnect() async {}
    func sendTyping(conversationID: String) async {
        typing.withLock { $0.append(conversationID) }
    }
}

extension DirectMessage {
    static func sample(
        _ id: String,
        in conversationID: String = "c1",
        from senderID: String = UserSummary.bob.id,
        content: String = "Salut",
        sharedVideoID: String? = nil,
        at date: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> DirectMessage {
        DirectMessage(
            id: id,
            conversationID: conversationID,
            senderID: senderID,
            content: content,
            sharedVideo: sharedVideoID.map { SharedVideo(id: $0, available: true, thumbnailURL: nil, description: nil, author: .bob) },
            createdAt: date
        )
    }
}

extension Conversation {
    static func sample(
        _ id: String,
        with participant: UserSummary = .bob,
        status: ConversationStatus = .direct,
        lastMessage: DirectMessage? = nil,
        unreadCount: Int = 0,
        canSend: Bool = true,
        remaining: Int? = nil,
        blockedByMe: Bool = false
    ) -> Conversation {
        Conversation(
            id: id,
            participant: participant,
            status: status,
            lastMessage: lastMessage,
            unreadCount: unreadCount,
            participantLastReadMessageID: nil,
            canSend: canSend,
            remainingRequestMessages: remaining,
            blockedByMe: blockedByMe,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
