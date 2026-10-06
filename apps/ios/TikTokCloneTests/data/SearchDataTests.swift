import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@Suite("RemoteSearchRepository (ADR-049)")
struct SearchDataTests {
    @Test("comptes : résumé, abonnés, relation présente ou absente, curseur")
    func accounts() async throws {
        let body = #"""
            {"items":[{"user":{"id":"u1","username":"lea","displayName":"Léa","avatarUrl":null},"followersCount":12,
            "viewer":{"following":true,"followedBy":false}},
            {"user":{"id":"u2","username":"galea","displayName":"Gaëlle","avatarUrl":null},"followersCount":3}],"nextCursor":"c2"}
            """#
        let log = RequestLog()
        let client = makeClient(
            transport: MockTransport { request, operationID in
                log.record(request, operationID)
                return json(.ok, body)
            })
        let page = try await RemoteSearchRepository(client: client).searchAccounts(query: "lea", cursor: nil)
        #expect(page.results.map(\.user.username) == ["lea", "galea"])
        #expect(page.results[0].followersCount == 12)
        #expect(page.results[0].viewer == FollowViewer(following: true, followedBy: false))
        #expect(page.results[1].viewer == nil)
        #expect(page.nextCursor == "c2")
        #expect(log.operations == ["searchUsers"])
    }

    @Test("hashtags : recherche, tendances, page d'un hashtag ; nom invalide → introuvable")
    func hashtags() async throws {
        let client = makeClient(
            transport: MockTransport { _, operationID in
                switch operationID {
                case "searchHashtags", "listTrendingHashtags": json(.ok, #"{"items":[{"name":"été","videosCount":4}]}"#)
                case "getHashtag": json(.badRequest, errorJSON(400, "Hashtag invalide"))
                default: json(.ok, #"{"items":[],"nextCursor":null}"#)
                }
            })
        let repository = RemoteSearchRepository(client: client)
        #expect(try await repository.searchHashtags(prefix: "ét", limit: 5) == [Hashtag(name: "été", videosCount: 4)])
        #expect(try await repository.trendingHashtags() == [Hashtag(name: "été", videosCount: 4)])
        await #expect(throws: AppError.notFound) { try await repository.hashtag(name: "a b") }
        let videos = try await RemoteVideoListRepository(client: client).page(of: .hashtag(name: "été"), cursor: nil)
        #expect(videos.videos.isEmpty)
    }
}
