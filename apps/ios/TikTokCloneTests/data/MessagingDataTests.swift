import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

private let bobJSON = #"{"id":"bob-id","username":"bob","displayName":"Bob","avatarUrl":null}"#

private let messageJSON = """
    {"id":"m1","conversationId":"c1","senderId":"bob-id","content":"",\
    "sharedVideo":{"id":"v1","available":true,"thumbnailUrl":"http://cdn.test/v1/thumbnail.jpg","hlsUrl":"http://cdn.test/v1/master.m3u8",\
    "description":"Démo","author":\(bobJSON)},"createdAt":"2026-09-26T08:00:00.123Z"}
    """

private let conversationJSON = """
    {"id":"c1","participant":\(bobJSON),"status":"requestSent","lastMessage":\(messageJSON),"unreadCount":2,\
    "participantLastReadMessageId":null,"canSend":true,"remainingRequestMessages":2,"blockedByMe":false,"createdAt":"2026-09-26T07:00:00.000Z"}
    """

@Suite("Messagerie : API")
struct MessagingDataTests {
    @Test("conversations : participant, statut, dernier message avec vidéo partagée, limites de la demande")
    func mapping() async throws {
        let repository = RemoteMessagingRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    json(.ok, #"{"items":[\#(conversationJSON)],"nextCursor":"m1"}"#)
                }))
        let page = try await repository.conversations(cursor: nil)
        let conversation = try #require(page.conversations.first)
        #expect(conversation.participant.username == "bob")
        #expect(conversation.status == .requestSent)
        #expect(conversation.unreadCount == 2)
        #expect(conversation.remainingRequestMessages == 2)
        #expect(conversation.lastMessage?.sharedVideo?.thumbnailURL?.absoluteString == "http://cdn.test/v1/thumbnail.jpg")
        #expect(conversation.lastMessage?.sharedVideo?.author?.username == "bob")
        #expect(conversation.lastMessage?.preview(ownID: "alice-id") == "Vidéo partagée")
        #expect(page.nextCursor == "m1")
    }

    @Test("vidéo partagée supprimée depuis : indisponible, sans miniature ni auteur")
    func unavailableVideo() async throws {
        let body = """
            {"items":[{"id":"m1","conversationId":"c1","senderId":"bob-id","content":"Regarde",\
            "sharedVideo":{"id":"v1","available":false,"thumbnailUrl":null,"hlsUrl":null,"description":null},\
            "createdAt":"2026-09-26T08:00:00.123Z"}],"nextCursor":null}
            """
        let repository = RemoteMessagingRepository(client: makeClient(transport: MockTransport { _, _ in json(.ok, body) }))
        let message = try #require(try await repository.messages(conversationID: "c1", cursor: nil).messages.first)
        #expect(message.sharedVideo == SharedVideo(id: "v1", available: false, thumbnailURL: nil, description: nil, author: nil))
        #expect(message.content == "Regarde")
    }

    @Test("envoi : 429 → délai de l'en-tête Retry-After ; 403 → message de l'API ; texte et vidéo envoyés")
    func sendErrors() async throws {
        let tooMany = RemoteMessagingRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    var response = HTTPResponse(status: .tooManyRequests, headerFields: [.contentType: "application/json"])
                    response.headerFields[HTTPField.Name("Retry-After")!] = "42"
                    return (response, HTTPBody(errorJSON(429, "Trop de messages")))
                }))
        await #expect(throws: AppError.rateLimited(retryAfter: 42)) {
            try await tooMany.send(conversationID: "c1", content: "Salut", videoID: nil)
        }

        let forbidden = RemoteMessagingRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    json(.forbidden, errorJSON(403, "Impossible d’écrire à ce compte"))
                }))
        await #expect(throws: AppError.rejected("Impossible d’écrire à ce compte")) {
            try await forbidden.send(conversationID: "c1", content: "Salut", videoID: nil)
        }

        let created = RemoteMessagingRepository(
            client: makeClient(
                transport: MockTransport { request, operation in
                    #expect(operation == "sendMessage")
                    #expect(request.path == "/conversations/c1/messages")
                    return json(.created, messageJSON)
                }))
        let message = try await created.send(conversationID: "c1", content: nil, videoID: "v1")
        #expect(message.sharedVideo?.id == "v1")
    }

    @Test("badges, marquage lu, demandes ; retrait déjà fait (404) sans erreur ; 401 → session expirée")
    func badgesAndActions() async throws {
        let log = RequestLog()
        let repository = RemoteMessagingRepository(
            client: makeClient(
                transport: MockTransport { request, operation in
                    log.record(request, operation)
                    switch operation {
                    case "countUnreadConversations", "markConversationRead": return json(.ok, #"{"unreadCount":1,"requestCount":3}"#)
                    case "acceptMessageRequest", "openConversation": return json(.ok, conversationJSON)
                    case "declineMessageRequest", "deleteConversation": return (HTTPResponse(status: .noContent), nil)
                    case "deleteMessage": return json(.notFound, errorJSON(404, "Message introuvable"))
                    default: return json(.ok, "{}")
                    }
                }))
        #expect(try await repository.badges() == MessagingBadges(unreadConversations: 1, pendingRequests: 3))
        #expect(try await repository.markRead(conversationID: "c1", upToID: "m1") == MessagingBadges(unreadConversations: 1, pendingRequests: 3))
        #expect(try await repository.accept(conversationID: "c1").id == "c1")
        #expect(try await repository.open(username: "bob").participant.username == "bob")
        try await repository.decline(conversationID: "c1")
        try await repository.deleteConversation(id: "c1")
        try await repository.deleteMessage(id: "m1")
        #expect(
            log.operations == [
                "countUnreadConversations", "markConversationRead", "acceptMessageRequest", "openConversation",
                "declineMessageRequest", "deleteConversation", "deleteMessage",
            ])

        let expired = RemoteMessagingRepository(client: makeClient(transport: MockTransport { _, _ in json(.unauthorized, errorJSON(401, "x")) }))
        await #expect(throws: AppError.sessionExpired) { try await expired.badges() }
    }
}

@Suite("Messagerie : temps réel")
struct MessagingRealtimeTests {
    let decoder = RealtimeEventDecoder()
    let badges = #""unreadConversations":1,"pendingRequests":2"#
    let expectedBadges = MessagingBadges(unreadConversations: 1, pendingRequests: 2)

    @Test("événements de la messagerie traduits, avec les badges")
    func events() throws {
        guard
            case .messageCreated(let message, let created)? = decoder.decode(
                #"{"event":"messageCreated","data":{"message":\#(messageJSON),\#(badges)}}"#)
        else {
            Issue.record("messageCreated attendu")
            return
        }
        #expect(message.id == "m1")
        #expect(created == expectedBadges)
        #expect(
            decoder.decode(#"{"event":"messageDeleted","data":{"conversationId":"c1","messageId":"m1",\#(badges)}}"#)
                == .messageDeleted(conversationID: "c1", messageID: "m1", expectedBadges))
        #expect(
            decoder.decode(#"{"event":"conversationRead","data":{"conversationId":"c1","readerId":"bob-id","lastReadMessageId":"m1",\#(badges)}}"#)
                == .conversationRead(conversationID: "c1", readerID: "bob-id", lastReadMessageID: "m1", expectedBadges))
        #expect(
            decoder.decode(#"{"event":"conversationAccepted","data":{"conversationId":"c1",\#(badges)}}"#)
                == .conversationAccepted(conversationID: "c1", expectedBadges))
        #expect(
            decoder.decode(#"{"event":"conversationDeleted","data":{"conversationId":"c1",\#(badges)}}"#)
                == .conversationDeleted(conversationID: "c1", expectedBadges))
        #expect(
            decoder.decode(#"{"event":"typing","data":{"conversationId":"c1","userId":"bob-id"}}"#)
                == .typing(conversationID: "c1", userID: "bob-id"))
    }

    @Test("« en train d'écrire » encodé comme l'attend l'API")
    func typingMessage() throws {
        let text = try #require(RealtimeClientMessageEncoder.typing(conversationID: "c1"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["event"] as? String == "typing")
        #expect((object["data"] as? [String: Any])?["conversationId"] as? String == "c1")
    }

    @Test("« en train d'écrire » envoyé sur la connexion établie, ignoré sans connexion")
    func sendTyping() async {
        let sockets = FakeSocketFactory([])
        let channel = WebSocketRealtimeChannel(
            url: URL(string: "ws://api.test/realtime")!,
            sockets: sockets,
            accessToken: { "t1" },
            refreshToken: { _ in nil },
            pingInterval: .seconds(3600),
            pause: { _ in }
        )
        await channel.sendTyping(conversationID: "c0")
        await channel.connect()
        for await update in channel.updates where update == .connected { break }
        await channel.sendTyping(conversationID: "c1")
        // L'ordre des clés du JSON n'est pas fixe : comparer le contenu.
        let sent = sockets.sent.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(sent.count == 1)
        #expect(sent.first?["event"] as? String == "typing")
        #expect((sent.first?["data"] as? [String: Any])?["conversationId"] as? String == "c1")
        await channel.disconnect()
    }
}
