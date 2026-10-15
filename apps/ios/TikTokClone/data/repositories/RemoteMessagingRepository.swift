import Foundation
import TikTokAPI

// Messagerie directe par l'API (module messaging).
struct RemoteMessagingRepository: MessagingRepository {
    static let pageSize = 20

    let client: Client

    func conversations(cursor: String?) async throws -> ConversationPage {
        switch try await mappingErrors({ try await client.listConversations(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
        case .ok(let ok): return ConversationPage(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func requests(cursor: String?) async throws -> ConversationPage {
        switch try await mappingErrors({ try await client.listMessageRequests(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
        case .ok(let ok): return ConversationPage(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func searchMessages(query: String) async throws -> [MessageSearchResult] {
        switch try await mappingErrors({ try await client.searchMessages(query: .init(q: query)) }) {
        case .ok(let ok):
            return try ok.body.json.items.map {
                MessageSearchResult(
                    conversationID: $0.conversationId, messageID: $0.messageId, content: $0.content, createdAt: $0.createdAt,
                    participant: UserSummary($0.participant), sender: UserSummary($0.sender))
            }
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func open(username: String) async throws -> Conversation {
        switch try await mappingErrors({ try await client.openConversation(body: .json(.init(username: username))) }) {
        case .ok(let ok): return Conversation(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func conversation(id: String) async throws -> Conversation {
        switch try await mappingErrors({ try await client.getConversation(path: .init(id: id)) }) {
        case .ok(let ok): return Conversation(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func badges() async throws -> MessagingBadges {
        switch try await mappingErrors({ try await client.countUnreadConversations() }) {
        case .ok(let ok): return MessagingBadges(try ok.body.json)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func messages(conversationID: String, cursor: String?) async throws -> MessagePage {
        let output = try await mappingErrors {
            try await client.listMessages(path: .init(id: conversationID), query: .init(cursor: cursor, limit: Self.pageSize))
        }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return MessagePage(messages: page.items.map(DirectMessage.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func send(conversationID: String, content: String?, videoID: String?, clientMessageID: String?) async throws -> DirectMessage {
        let output = try await mappingErrors {
            try await client.sendMessage(
                path: .init(id: conversationID), body: .json(.init(content: content, videoId: videoID, clientMessageId: clientMessageID)))
        }
        switch output {
        case .created(let created): return DirectMessage(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        // Blocage, ou demande ayant atteint sa limite : le message de l'API dit lequel.
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound: throw AppError.notFound
        // Limite d'envoi : délai de l'en-tête Retry-After (une minute s'il manque).
        case .tooManyRequests(let error): throw AppError.rateLimited(retryAfter: max(1, error.headers.retryAfter ?? 60))
        // Identifiant d'envoi déjà pris par un message d'une autre conversation : ne devrait pas arriver.
        case .conflict: throw AppError.unexpected
        case .undocumented: throw AppError.unexpected
        }
    }

    func replyToStory(conversationID: String, storyID: String, content: String, clientMessageID: String) async throws -> DirectMessage {
        let output = try await mappingErrors {
            try await client.sendMessage(
                path: .init(id: conversationID),
                body: .json(.init(content: content, storyId: storyID, clientMessageId: clientMessageID)))
        }
        switch output {
        case .created(let created): return DirectMessage(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        // Story expirée, supprimée ou masquée entre-temps.
        case .notFound: throw AppError.rejected("Cette story n’est plus disponible.")
        case .tooManyRequests(let error): throw AppError.rateLimited(retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .conflict: throw AppError.unexpected
        case .undocumented: throw AppError.unexpected
        }
    }

    func shareLive(conversationID: String, liveID: String) async throws -> DirectMessage {
        let output = try await mappingErrors {
            try await client.sendMessage(path: .init(id: conversationID), body: .json(.init(liveId: liveID)))
        }
        switch output {
        case .created(let created): return DirectMessage(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        // Live terminé ou masqué entre-temps.
        case .notFound: throw AppError.rejected("Ce live est terminé.")
        case .tooManyRequests(let error): throw AppError.rateLimited(retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .conflict: throw AppError.unexpected
        case .undocumented: throw AppError.unexpected
        }
    }

    func markRead(conversationID: String, upToID: String?) async throws -> MessagingBadges {
        let output = try await mappingErrors {
            try await client.markConversationRead(path: .init(id: conversationID), body: .json(.init(upToId: upToID)))
        }
        switch output {
        case .ok(let ok): return MessagingBadges(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func accept(conversationID: String) async throws -> Conversation {
        switch try await mappingErrors({ try await client.acceptMessageRequest(path: .init(id: conversationID)) }) {
        case .ok(let ok): return Conversation(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func decline(conversationID: String) async throws {
        switch try await mappingErrors({ try await client.declineMessageRequest(path: .init(id: conversationID)) }) {
        case .noContent: return
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteConversation(id: String) async throws {
        switch try await mappingErrors({ try await client.deleteConversation(path: .init(id: id)) }) {
        case .noContent: return
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteMessage(id: String) async throws {
        switch try await mappingErrors({ try await client.deleteMessage(path: .init(id: id)) }) {
        case .noContent: return
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        // Déjà retiré (sur un autre appareil) : le résultat attendu est atteint.
        case .notFound: return
        case .undocumented: throw AppError.unexpected
        }
    }
}

// Mapping explicite (ADR-002) ; partagé avec les événements temps réel.
extension DirectMessage {
    init(_ dto: Components.Schemas.MessageResponse) {
        self.init(
            id: dto.id,
            conversationID: dto.conversationId,
            senderID: dto.senderId,
            content: dto.content,
            sharedVideo: dto.sharedVideo.map(SharedVideo.init),
            createdAt: dto.createdAt,
            clientMessageID: dto.clientMessageId,
            story: dto.story.map(RepliedStory.init),
            live: dto.live.map { SharedLive(id: $0.id, available: $0.available, title: $0.title ?? nil, host: $0.host.map(UserSummary.init)) }
        )
    }
}

extension RepliedStory {
    init(_ dto: Components.Schemas.MessageStoryResponse) {
        self.init(
            id: dto.id,
            available: dto.available,
            mediaType: dto.mediaType.map(StoryMediaType.init),
            thumbnailURL: dto.thumbnailUrl.flatMap(URL.init(string:))
        )
    }
}

extension SharedVideo {
    init(_ dto: Components.Schemas.SharedVideoResponse) {
        self.init(
            id: dto.id,
            available: dto.available,
            thumbnailURL: dto.thumbnailUrl.flatMap(URL.init(string:)),
            description: dto.description,
            author: dto.author.map(UserSummary.init)
        )
    }
}

extension Conversation {
    init(_ dto: Components.Schemas.ConversationResponse) {
        self.init(
            id: dto.id,
            participant: UserSummary(dto.participant),
            status: ConversationStatus(dto.status),
            lastMessage: dto.lastMessage.map(DirectMessage.init),
            unreadCount: dto.unreadCount,
            participantLastReadMessageID: dto.participantLastReadMessageId,
            canSend: dto.canSend,
            remainingRequestMessages: dto.remainingRequestMessages,
            blockedByMe: dto.blockedByMe,
            createdAt: dto.createdAt
        )
    }
}

extension ConversationPage {
    init(_ dto: Components.Schemas.ConversationPageResponse) {
        self.init(conversations: dto.items.map(Conversation.init), nextCursor: dto.nextCursor)
    }
}

extension ConversationStatus {
    init(_ dto: Components.Schemas.ConversationStatus) {
        switch dto {
        case .direct: self = .direct
        case .requestSent: self = .requestSent
        case .requestReceived: self = .requestReceived
        }
    }
}

extension MessagingBadges {
    init(_ dto: Components.Schemas.UnreadConversationsResponse) {
        self.init(unreadConversations: dto.unreadCount, pendingRequests: dto.requestCount)
    }
}
