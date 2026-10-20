import Foundation
import Synchronization
import Testing
import TikTokAPI

@testable import TikTokClone

@Suite("RemoteFeedRepository")
struct RemoteFeedRepositoryTests {
    static let item = """
        {"id":"v1","description":null,"visibility":"public","commentsEnabled":true,"soundShared":true,"aiGenerated":false,"hlsUrl":"http://localhost:9000/videos-hls/v1/master.m3u8",\
        "thumbnailUrl":"http://localhost:9000/videos-hls/v1/thumbnail.jpg","createdAt":"2026-09-25T10:00:00.000Z",\
        "viewsCount":10,"likesCount":2,"commentsCount":1,"favoritesCount":0,"sharesCount":3,"repostsCount":4,\
        "author":{"id":"u1","username":"bob","displayName":"Bob","avatarUrl":null}
        """

    @Test("mapping d'une page : compteurs, auteur, viewer présent ou absent, curseur")
    func mapping() async throws {
        let body =
            #"{"items":[\#(Self.item),"viewer":{"liked":true,"favorited":false,"reposted":false,"followingAuthor":true}},\#(Self.item.replacingOccurrences(of: "\"v1\"", with: "\"v2\""))}],"nextCursor":"abc"}"#
        let log = RequestLog()
        let client = makeClient(
            transport: MockTransport { request, operationID in
                log.record(request, operationID)
                return json(.ok, body)
            })
        let page = try await RemoteFeedRepository(client: client).page(cursor: nil)
        #expect(page.nextCursor == "abc")
        #expect(page.videos.map(\.id) == ["v1", "v2"])
        #expect(page.videos[0].viewer == ViewerState(liked: true, favorited: false, reposted: false, followingAuthor: true))
        #expect(page.videos[1].viewer == nil)
        #expect(page.videos[0].stats == VideoStats(views: 10, likes: 2, comments: 1, favorites: 0, shares: 3, reposts: 4))
        #expect(page.videos[0].author.username == "bob")
        #expect(page.videos[0].hlsURL.absoluteString.hasSuffix("/v1/master.m3u8"))
        #expect(log.operations == ["getFeed"])
    }

    @Test("historique de visionnage (ADR-057) : date de la dernière vue, absente ailleurs")
    func viewedAt() async throws {
        let body =
            #"{"items":[\#(Self.item),"viewedAt":"2026-10-15T12:30:00.000Z"},\#(Self.item.replacingOccurrences(of: "\"v1\"", with: "\"v2\""))}],"nextCursor":null}"#
        let client = makeClient(transport: MockTransport { _, _ in json(.ok, body) })
        let page = try await RemoteFeedRepository(client: client).page(cursor: nil)
        #expect(page.videos[0].viewedAt == ISO8601DateFormatter().date(from: "2026-10-15T12:30:00Z"))
        #expect(page.videos[1].viewedAt == nil)
    }

    @Test("feed des abonnements (ADR-048) : page, curseur transmis ; 401 → session expirée")
    func following() async throws {
        let log = RequestLog()
        let path = Mutex<String?>(nil)
        let client = makeClient(
            transport: MockTransport { request, operationID in
                log.record(request, operationID)
                path.withLock { $0 = request.path }
                return json(.ok, #"{"items":[\#(Self.item)}],"nextCursor":null}"#)
            })
        let page = try await RemoteFeedRepository(client: client).followingPage(cursor: "c1")
        #expect(page.videos.map(\.id) == ["v1"])
        #expect(page.nextCursor == nil)
        #expect(log.operations == ["getFollowingFeed"])
        #expect(path.withLock { $0 }?.contains("cursor=c1") == true)

        let expired = makeClient(transport: MockTransport { _, _ in json(.unauthorized, errorJSON(401, "x")) })
        await #expect(throws: AppError.sessionExpired) { try await RemoteFeedRepository(client: expired).followingPage(cursor: nil) }
    }

    @Test("feed des amis (ADR-054) : page, curseur transmis ; 401 → session expirée")
    func friends() async throws {
        let log = RequestLog()
        let client = makeClient(
            transport: MockTransport { request, operationID in
                log.record(request, operationID)
                return json(.ok, #"{"items":[\#(Self.item)}],"nextCursor":"c2"}"#)
            })
        let page = try await RemoteFeedRepository(client: client).friendsPage(cursor: "c1")
        #expect(page.videos.map(\.id) == ["v1"])
        #expect(page.nextCursor == "c2")
        #expect(log.operations == ["getFriendsFeed"])

        let expired = makeClient(transport: MockTransport { _, _ in json(.unauthorized, errorJSON(401, "x")) })
        await #expect(throws: AppError.sessionExpired) { try await RemoteFeedRepository(client: expired).friendsPage(cursor: nil) }
    }

    @Test("vue : 204 accepté, vidéo supprimée ignorée, 401 → session expirée")
    func recordView() async throws {
        for (status, expected) in [(HTTPResponse.Status.noContent, nil), (.notFound, nil), (.unauthorized, AppError.sessionExpired)] {
            let client = makeClient(
                transport: MockTransport { _, _ in
                    status == .noContent ? (HTTPResponse(status: status), nil) : json(status, errorJSON(status.code, "x"))
                })
            let repository = RemoteViewHistoryRepository(client: client)
            if let expected {
                await #expect(throws: expected) { try await repository.recordView(videoID: "v1") }
            } else {
                try await repository.recordView(videoID: "v1")
            }
        }
    }
}
