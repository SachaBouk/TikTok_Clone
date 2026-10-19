import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

// Vidéos privées (ADR-061) : choix à la publication, changement depuis la feuille de partage, onglet « cadenas ».
@MainActor
@Suite("Vidéos privées")
struct PrivateVideosTests {
    let videos = FakeVideoPublishingRepository()
    let store = InMemoryUploadStore()

    func makeInteractions(signedIn: Bool = true) async -> VideoInteractionsModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        return VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: FakeInteractionRepository()),
            setFollow: SetFollowUseCase(interactions: FakeInteractionRepository()),
            recordShare: ShareVideoUseCase(interactions: FakeInteractionRepository()),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            setVisibility: SetVideoVisibilityUseCase(videos: videos),
            session: session,
            analytics: makeAnalytics()
        )
    }

    // Vidéo d'alice, le compte connecté.
    var mine: FeedVideo { FeedVideo.sample("v1", author: "alice").byAlice }

    @Test("publication : la visibilité choisie part avec l'envoi, et une story reste publique")
    func publication() async throws {
        let create = CreatePublicationUseCase(store: store, makeID: { "u1" })
        let upload = try create(file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "", userID: "a", visibility: .onlyMe)
        #expect(upload.visibility == .onlyMe)
        let story = try create(file: store.addPickedFile("s.mov", Data("0123".utf8)), description: "", userID: "a", kind: .story, visibility: .onlyMe)
        #expect(story.visibility == .everyone)

        let use = UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: FakePartTransport(), store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.visibility(of: "vid-1") == .onlyMe)
    }

    @Test("envoi enregistré avant les vidéos privées : relu public")
    func legacyPendingUpload() throws {
        let json = #"{"id":"u1","userID":"a","fileName":"f","contentType":"video/mp4","fileSize":1,"createdAt":0}"#
        let upload = try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8))
        #expect(upload.visibility == .everyone)
    }

    @Test("rendre privée : tout de suite à l'écran, version incrémentée ; erreur : retour à l'état d'avant")
    func toggle() async {
        let interactions = await makeInteractions()
        #expect(await interactions.setVisibility(.onlyMe, of: mine) == nil)
        #expect(interactions.display(mine).visibility == .onlyMe)
        #expect(videos.visibility(of: "v1") == .onlyMe)
        #expect(interactions.visibilityVersion == 1)
        // Déjà privée : rien n'est envoyé.
        #expect(await interactions.setVisibility(.onlyMe, of: mine) == nil)
        #expect(interactions.visibilityVersion == 1)

        videos.state.withLock { $0.visibilityError = .network }
        #expect(await interactions.setVisibility(.everyone, of: mine) == AppError.network.message)
        #expect(interactions.display(mine).visibility == .onlyMe)
        #expect(interactions.visibilityVersion == 1)
    }

    @Test("la vidéo d'un autre ne change pas de visibilité")
    func notOwn() async {
        let interactions = await makeInteractions()
        let others = FeedVideo.sample("v2")
        #expect(await interactions.setVisibility(.onlyMe, of: others) == nil)
        #expect(videos.visibility(of: "v2") == nil)
    }

    @Test("onglet « cadenas » : sur son profil seulement, entre « Vidéos » et « Republications »")
    func grids() {
        #expect(ProfileGrid.available(isOwn: true) == [.videos, .privateVideos, .reposts, .favorites, .likes])
        #expect(ProfileGrid.available(isOwn: false) == [.videos, .reposts])
        #expect(ProfileGrid.privateVideos.systemImage == "lock")
        #expect(VideoList(.privateVideos, username: "alice") == .myPrivateVideos)
        #expect(VideoVisibility.onlyMe.label == "Toi uniquement")
    }

    @Test("API : grille privée, changement de visibilité, visibilité lue dans le feed")
    func remote() async throws {
        let log = RequestLog()
        let item = RemoteFeedRepositoryTests.item.replacingOccurrences(of: #""visibility":"public""#, with: #""visibility":"private""#) + "}"
        let client = makeClient(
            transport: MockTransport { request, operationID in
                log.record(request, operationID)
                switch operationID {
                case "listMyPrivateVideos": return json(.ok, #"{"items":["# + item + #"],"nextCursor":null}"#)
                default:
                    return json(
                        .ok,
                        #"{"id":"v1","userId":"u","description":null,"status":"ready","visibility":"private","commentsEnabled":true,"hlsUrl":null,"thumbnailUrl":null,"createdAt":"2026-09-25T12:00:00.000Z"}"#
                    )
                }
            })
        let page = try await RemoteVideoListRepository(client: client).page(of: .myPrivateVideos, cursor: nil)
        #expect(page.videos.map(\.visibility) == [.onlyMe])
        try await RemoteVideoPublishingRepository(client: client).setVisibility(videoID: "v1", visibility: .onlyMe)
        #expect(log.operations == ["listMyPrivateVideos", "setVideoVisibility"])
    }
}

extension FeedVideo {
    // La même vidéo, publiée par alice (le compte connecté des tests).
    var byAlice: FeedVideo {
        FeedVideo(
            id: id, description: description, hlsURL: hlsURL, thumbnailURL: thumbnailURL, createdAt: createdAt, stats: stats, author: .alice,
            viewer: viewer)
    }
}
