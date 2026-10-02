import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@Suite("RemoteInteractionRepository")
struct RemoteInteractionRepositoryTests {
    func repository(_ respond: @escaping @Sendable (String) -> (HTTPResponse, HTTPBody?), log: RequestLog = RequestLog())
        -> RemoteInteractionRepository
    {
        RemoteInteractionRepository(
            client: makeClient(
                transport: MockTransport { request, operationID in
                    log.record(request, operationID)
                    return respond(operationID)
                }))
    }

    @Test("chaque réaction appelle sa route et renvoie l'état de l'API")
    func reactions() async throws {
        let log = RequestLog()
        let repo = repository({ _ in json(.ok, #"{"active":true,"count":7}"#) }, log: log)
        for kind in ReactionKind.allCases {
            for active in [true, false] {
                #expect(try await repo.setReaction(kind, videoID: "v1", active: active) == InteractionState(active: true, count: 7))
            }
        }
        #expect(log.operations == ["likeVideo", "unlikeVideo", "favoriteVideo", "unfavoriteVideo", "repostVideo", "unrepostVideo"])
    }

    @Test("429 (ADR-039) : réactions, abonnements, commentaires, avec le délai de Retry-After")
    func rateLimited() async {
        await #expect(throws: AppError.tooManyActions(.reactions, retryAfter: 42)) {
            try await repository { _ in tooManyRequests(retryAfter: 42) }.setReaction(.repost, videoID: "v1", active: true)
        }
        await #expect(throws: AppError.tooManyActions(.follows, retryAfter: 3600)) {
            try await repository { _ in tooManyRequests(retryAfter: 3600) }.setFollow(username: "bob", active: true)
        }
        await #expect(throws: AppError.tooManyActions(.comments, retryAfter: 90)) {
            try await repository { _ in tooManyRequests(retryAfter: 90) }.addComment(videoID: "v1", content: "Salut")
        }
        #expect(AppError.tooManyActions(.reactions, retryAfter: 42).message == "Trop de réactions en peu de temps. Réessaie dans 42 s.")
        #expect(AppError.tooManyActions(.comments, retryAfter: 90).message == "Trop de commentaires en peu de temps. Réessaie dans 2 min.")
        #expect(AppError.tooManyActions(.follows, retryAfter: 3600).message == "Trop d’abonnements en peu de temps. Réessaie dans 1 h.")
        #expect(AppError.tooManyActions(.uploads, retryAfter: 7201).message == "Trop de vidéos envoyées récemment. Réessaie dans 3 h.")
    }

    @Test("403 → blocage, 404 → introuvable, 401 → session expirée")
    func errors() async {
        await #expect(throws: AppError.blocked) {
            try await repository { _ in json(.forbidden, errorJSON(403, "bloqué")) }.setReaction(.like, videoID: "v1", active: true)
        }
        await #expect(throws: AppError.notFound) {
            try await repository { _ in json(.notFound, errorJSON(404, "x")) }.setFollow(username: "bob", active: true)
        }
        await #expect(throws: AppError.sessionExpired) {
            try await repository { _ in json(.unauthorized, errorJSON(401, "x")) }.addComment(videoID: "v1", content: "Salut")
        }
        await #expect(throws: AppError.rejected("Impossible de se suivre soi-même")) {
            try await repository { _ in json(.badRequest, errorJSON(400, "Impossible de se suivre soi-même")) }.setFollow(
                username: "alice", active: true)
        }
    }

    @Test("commentaires : mapping de la page ; suppression déjà faite (404) acceptée")
    func comments() async throws {
        let body =
            #"{"items":[{"id":"c1","videoId":"v1","content":"Top","createdAt":"2026-09-25T10:00:00.000Z","author":{"id":"u1","username":"bob","displayName":"Bob","avatarUrl":null}}],"nextCursor":"c1"}"#
        let page = try await repository { _ in json(.ok, body) }.comments(videoID: "v1", cursor: nil)
        #expect(page.comments.map(\.content) == ["Top"])
        #expect(page.comments[0].author.username == "bob")
        #expect(page.nextCursor == "c1")
        try await repository { _ in json(.notFound, errorJSON(404, "x")) }.deleteComment(id: "c1")
    }

    @Test("partage : total renvoyé")
    func share() async throws {
        #expect(try await repository { _ in json(.ok, #"{"sharesCount":4}"#) }.recordShare(videoID: "v1") == 4)
    }
}
