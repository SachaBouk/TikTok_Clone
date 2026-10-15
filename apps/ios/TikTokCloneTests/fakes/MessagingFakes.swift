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
        var sent: [(conversationID: String, content: String?, videoID: String?, clientMessageID: String?)] = []
        var markedUpTo: [String?] = []
        var error: AppError?
        var sendError: AppError?
        // Le message est enregistré, puis la réponse se perd (coupure) : l'envoi échoue en `.network`.
        var losesResponse = false
        // Identifiants « n101 »… : après les « mNN » des tests (ordre des UUID v7).
        var nextID = 100
        var repliedStoryIDs: [String] = []
        // Recherche dans les messages (ADR-058) : résultats rendus tels quels, recherches reçues.
        var searchResults: [MessageSearchResult] = []
        var searches: [String] = []
    }

    let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    var markedUpTo: [String?] { state.withLock { $0.markedUpTo } }
    var sentContents: [String?] { state.withLock { $0.sent.map(\.content) } }
    var sentVideoIDs: [String?] { state.withLock { $0.sent.map(\.videoID) } }
    var sentClientMessageIDs: [String?] { state.withLock { $0.sent.map(\.clientMessageID) } }
    func losesResponse(_ loses: Bool) { state.withLock { $0.losesResponse = loses } }
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

    func searchMessages(query: String) async throws -> [MessageSearchResult] {
        try state.withLock { state in
            state.searches.append(query)
            if let error = state.error { throw error }
            return state.searchResults.filter { $0.content.localizedCaseInsensitiveContains(query) }
        }
    }

    func requests(cursor: String?) async throws -> ConversationPage {
        try page(cursor: cursor, call: "requests") { $0.status == .requestReceived }
    }

    func open(username: String) async throws -> Conversation {
        try state.withLock { state in
            state.calls.append("open:\(username)")
            if let error = state.error { throw error }
            if let existing = state.conversations.values.first(where: { $0.participant?.username == username }) { return existing }
            let conversation = Conversation.sample(
                "c-\(username)", with: UserSummary(id: "\(username)-id", username: username, displayName: username.capitalized, avatarURL: nil))
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

    // Comme l'API (ADR-044) : un envoi déjà enregistré avec le même `clientMessageID` rend le message existant.
    func send(conversationID: String, content: String?, videoID: String?, clientMessageID: String?) async throws -> DirectMessage {
        try state.withLock { state in
            state.sent.append((conversationID, content, videoID, clientMessageID))
            if let clientMessageID, let existing = state.messages[conversationID]?.first(where: { $0.clientMessageID == clientMessageID }) {
                return existing
            }
            if let error = state.sendError ?? state.error { throw error }
            state.nextID += 1
            var message = DirectMessage.sample(
                "n\(state.nextID)", in: conversationID, from: UserProfile.alice.id, content: content ?? "",
                sharedVideoID: videoID)
            message.clientMessageID = clientMessageID
            state.messages[conversationID, default: []].append(message)
            if var conversation = state.conversations[conversationID] {
                conversation.lastMessage = message
                state.conversations[conversationID] = conversation
            }
            if state.losesResponse { throw AppError.network }
            return message
        }
    }

    func replyToStory(conversationID: String, storyID: String, content: String, clientMessageID: String) async throws -> DirectMessage {
        var message = try await send(conversationID: conversationID, content: content, videoID: nil, clientMessageID: clientMessageID)
        message.story = RepliedStory(id: storyID, available: true, mediaType: .photo, thumbnailURL: nil)
        state.withLock { $0.repliedStoryIDs.append(storyID) }
        return message
    }

    func shareLive(conversationID: String, liveID: String) async throws -> DirectMessage {
        var message = try await send(conversationID: conversationID, content: nil, videoID: nil, clientMessageID: nil)
        message.live = SharedLive(id: liveID, available: true, title: nil, host: nil)
        return message
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

    // MARK: - Chats de groupe (ADR-059)

    func createGroup(userIDs: [String], name: String?) async throws -> Conversation {
        try state.withLock { state in
            state.calls.append("createGroup:\(userIDs.joined(separator: ","))")
            if let error = state.error { throw error }
            state.nextID += 1
            let id = "g\(state.nextID)"
            let members = [UserSummary.alice] + userIDs.map { UserSummary(id: $0, username: $0, displayName: $0.capitalized, avatarURL: nil) }
            var created = DirectMessage.sample("n\(state.nextID)", in: id, from: UserSummary.alice.id, content: "")
            created.sender = .alice
            created.event = GroupEvent(kind: .created, user: nil, name: nil)
            let conversation = Conversation.group(id, name: name, members: members, lastMessage: created)
            state.conversations[id] = conversation
            state.messages[id] = [created]
            return conversation
        }
    }

    func renameGroup(conversationID: String, name: String?) async throws -> Conversation {
        try changeGroup(conversationID, call: "rename:\(name ?? "-")") { $0.name = name }
    }

    func addGroupMembers(conversationID: String, userIDs: [String]) async throws -> Conversation {
        try changeGroup(conversationID, call: "add:\(userIDs.joined(separator: ","))") { group in
            group.members += userIDs.map {
                GroupMember(user: UserSummary(id: $0, username: $0, displayName: $0.capitalized, avatarURL: nil), joinedAt: .now)
            }
        }
    }

    func removeGroupMember(conversationID: String, userID: String) async throws {
        _ = try changeGroup(conversationID, call: "remove:\(userID)") { $0.members.removeAll { $0.user.id == userID } }
    }

    func leaveGroup(conversationID: String) async throws {
        try state.withLock { state in
            state.calls.append("leave")
            if let error = state.error { throw error }
            state.conversations[conversationID] = nil
        }
    }

    func setGroupMuted(conversationID: String, muted: Bool) async throws {
        _ = try changeGroup(conversationID, call: muted ? "mute" : "unmute") { $0.muted = muted }
    }

    private func changeGroup(_ id: String, call: String, _ change: (inout GroupChat) -> Void) throws -> Conversation {
        try state.withLock { state in
            state.calls.append(call)
            if let error = state.error { throw error }
            guard var conversation = state.conversations[id], var group = conversation.group else { throw AppError.notFound }
            change(&group)
            conversation.group = group
            state.conversations[id] = conversation
            return conversation
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
    // Groupe (ADR-059) : Alice (le compte connecté) et les membres donnés, le premier administrateur.
    static func group(
        _ id: String, name: String? = nil, members: [UserSummary], lastMessage: DirectMessage? = nil, unreadCount: Int = 0
    ) -> Conversation {
        Conversation(
            id: id,
            participant: nil,
            group: GroupChat(
                name: name, adminID: members.first?.id ?? UserSummary.alice.id, muted: false,
                members: members.enumerated().map { GroupMember(user: $1, joinedAt: Date(timeIntervalSince1970: 1_799_999_000 + Double($0))) }),
            status: .direct,
            lastMessage: lastMessage,
            unreadCount: unreadCount,
            participantLastReadMessageID: nil,
            canSend: true,
            remainingRequestMessages: nil,
            blockedByMe: false,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

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
