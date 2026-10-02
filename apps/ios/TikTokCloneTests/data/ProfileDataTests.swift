import Foundation
import Synchronization
import Testing
import TikTokAPI

@testable import TikTokClone

private let bobJSON = """
    {"id":"0192f3a0-0000-7000-8000-000000000002","username":"bob","displayName":"Bob","avatarUrl":null,"bio":null,\
    "followersCount":10,"followingCount":2,"createdAt":"2026-01-01T12:00:00.123Z"}
    """

private let userSummaryJSON = #"{"id":"u2","username":"bob","displayName":"Bob","avatarUrl":"http://cdn.test/bob.jpg"}"#

private func client(_ respond: @escaping @Sendable (String) -> (HTTPResponse, HTTPBody?), log: RequestLog = RequestLog()) -> Client {
    makeClient(
        transport: MockTransport { request, operationID in
            log.record(request, operationID)
            return respond(operationID)
        })
}

@Suite("Profil : dépôts distants")
struct ProfileDataTests {
    @Test("profil public ; 404 → introuvable ; 410 → compte suspendu (ADR-037)")
    func profile() async throws {
        let profile = try await RemoteProfileRepository(client: client { _ in json(.ok, bobJSON) }).profile(username: "bob")
        #expect(profile.username == "bob")
        #expect(profile.bio == nil)
        await #expect(throws: AppError.notFound) {
            try await RemoteProfileRepository(client: client { _ in json(.notFound, errorJSON(404, "x")) }).profile(username: "x")
        }
        await #expect(throws: AppError.profileSuspended) {
            try await RemoteProfileRepository(client: client { _ in json(.gone, errorJSON(410, "Compte suspendu : @x")) }).profile(username: "x")
        }
    }

    @Test("modification : 409 → pseudo déjà pris, 400 → message de l'API")
    func update() async {
        await #expect(throws: AppError.rejected("Ce pseudo est déjà pris.")) {
            try await RemoteProfileRepository(client: client { _ in json(.conflict, errorJSON(409, "x")) })
                .updateMyProfile(ProfileChanges(username: "bob"))
        }
        await #expect(throws: AppError.rejected("bio trop longue")) {
            try await RemoteProfileRepository(client: client { _ in json(.badRequest, errorJSON(400, "bio trop longue")) })
                .updateMyProfile(ProfileChanges(bio: "x"))
        }
    }

    @Test("photo : URL signée ; image refusée (400) ; suppression du compte déjà faite (404) sans erreur")
    func avatarAndDeletion() async throws {
        let upload = try await RemoteProfileRepository(
            client: client { _ in
                json(.created, #"{"avatarId":"a1","uploadUrl":"http://localhost:9000/avatars/u/a1?sig=1","expiresAt":"2026-09-26T10:15:00.000Z"}"#)
            }
        ).createAvatarUpload(type: .jpeg, size: 1000)
        #expect(upload.id == "a1")
        #expect(upload.uploadURL.absoluteString == "http://localhost:9000/avatars/u/a1?sig=1")

        await #expect(throws: AppError.self) {
            try await RemoteProfileRepository(client: client { _ in json(.badRequest, errorJSON(400, "x")) }).setAvatar(id: "a1")
        }
        try await RemoteProfileRepository(client: client { _ in json(.notFound, errorJSON(404, "x")) }).deleteAccount()
    }

    @Test("abonnés : relation du compte connecté facultative (invité)")
    func follows() async throws {
        let body = """
            {"items":[{"user":\(userSummaryJSON),"followedAt":"2026-09-20T10:00:00.000Z","viewer":{"following":true,"followedBy":false}},\
            {"user":\(userSummaryJSON),"followedAt":"2026-09-19T10:00:00.000Z"}],"nextCursor":"c2"}
            """
        let log = RequestLog()
        let page = try await RemoteRelationshipRepository(client: client({ _ in json(.ok, body) }, log: log))
            .follows(.followers, username: "alice", cursor: nil)
        #expect(page.entries.map(\.viewer) == [FollowViewer(following: true, followedBy: false), nil])
        #expect(page.entries.first?.user.avatarURL?.absoluteString == "http://cdn.test/bob.jpg")
        #expect(page.nextCursor == "c2")
        #expect(log.operations == ["listFollowers"])
    }

    @Test("relation, blocage et comptes bloqués")
    func relationshipAndBlocks() async throws {
        let log = RequestLog()
        let repository = RemoteRelationshipRepository(
            client: client(
                { operation in
                    switch operation {
                    case "getRelationship": json(.ok, #"{"following":true,"followedBy":true,"blockedByMe":false}"#)
                    case "listBlockedUsers": json(.ok, #"{"items":[\#(userSummaryJSON)]}"#)
                    default: (HTTPResponse(status: .noContent), nil)
                    }
                }, log: log))
        #expect(try await repository.relationship(username: "bob") == Relationship(following: true, followedBy: true, blockedByMe: false))
        try await repository.setBlocked(true, username: "bob")
        try await repository.setBlocked(false, username: "bob")
        #expect(try await repository.blockedUsers().map(\.username) == ["bob"])
        #expect(log.operations == ["getRelationship", "blockUser", "unblockUser", "listBlockedUsers"])
    }

    @Test("relations par lot (« Suivre en retour ») : identifiants répétés dans la requête ; 401 → session expirée")
    func relationshipsBatch() async throws {
        let path = Mutex<String?>(nil)
        let repository = RemoteRelationshipRepository(
            client: makeClient(
                transport: MockTransport { request, _ in
                    path.withLock { $0 = request.path }
                    let u1 = #"{"userId":"u1","following":false,"followedBy":true,"blockedByMe":false}"#
                    let u2 = #"{"userId":"u2","following":true,"followedBy":true,"blockedByMe":false}"#
                    return json(.ok, #"{"items":["# + u1 + "," + u2 + "]}")
                }))
        let relationships = try await repository.relationships(userIDs: ["u1", "u2"])
        #expect(
            relationships == [
                "u1": Relationship(following: false, followedBy: true, blockedByMe: false),
                "u2": Relationship(following: true, followedBy: true, blockedByMe: false),
            ])
        #expect(path.withLock { $0 }?.hasSuffix("/users/me/relationships?userIds=u1&userIds=u2") == true)
        await #expect(throws: AppError.sessionExpired) {
            try await RemoteRelationshipRepository(client: makeClient(transport: MockTransport { _, _ in json(.unauthorized, errorJSON(401, "x")) }))
                .relationships(userIDs: ["u1"])
        }
    }

    @Test("listes de vidéos : chaque liste appelle sa route ; historique effaçable")
    func videoLists() async throws {
        let log = RequestLog()
        let repository = RemoteVideoListRepository(
            client: client(
                { operation in
                    operation.hasSuffix("History") && operation != "listMyHistory"
                        ? (HTTPResponse(status: .noContent), nil)
                        : json(.ok, #"{"items":[],"nextCursor":null}"#)
                }, log: log))
        for list in [VideoList.accountVideos(username: "bob"), .reposts(username: "bob"), .myFavorites, .myLikes, .myHistory] {
            #expect(try await repository.page(of: list, cursor: nil) == FeedPage(videos: [], nextCursor: nil))
        }
        try await repository.removeFromHistory(videoID: "0192f3a0-0000-7000-8000-00000000000a")
        try await repository.clearHistory()
        #expect(
            log.operations == [
                "listAccountVideos", "listReposts", "listMyFavorites", "listMyLikes", "listMyHistory", "removeFromHistory", "clearHistory",
            ])
    }

    @Test("historique des commentaires : commentaire et vidéo commentée")
    func commentHistory() async throws {
        let body = """
            {"items":[{"id":"c1","content":"Super","createdAt":"2026-09-20T10:00:00.000Z",\
            "video":{"id":"v1","thumbnailUrl":"http://cdn.test/v1/thumbnail.jpg","author":\(userSummaryJSON)}}],"nextCursor":null}
            """
        let page = try await RemoteInteractionRepository(client: client { _ in json(.ok, body) }).myComments(cursor: nil)
        #expect(page.entries.first?.content == "Super")
        #expect(page.entries.first?.video.author.username == "bob")
        #expect(page.entries.first?.video.thumbnailURL?.absoluteString == "http://cdn.test/v1/thumbnail.jpg")
    }
}
