import Foundation
import Testing

@testable import TikTokClone

// Commentaires désactivables (ADR-062) : choix à la publication, changement depuis la feuille de partage.
@MainActor
@Suite("Commentaires désactivables")
struct CommentSettingsTests {
    let videos = FakeVideoPublishingRepository()
    let store = InMemoryUploadStore()

    func makeInteractions() async -> VideoInteractionsModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        return VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: FakeInteractionRepository()),
            setFollow: SetFollowUseCase(interactions: FakeInteractionRepository()),
            recordShare: ShareVideoUseCase(interactions: FakeInteractionRepository()),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            setCommentsEnabled: SetCommentsEnabledUseCase(videos: videos),
            session: session,
            analytics: makeAnalytics()
        )
    }

    var mine: FeedVideo { FeedVideo.sample("v1", author: "alice").byAlice }

    @Test("publication : le choix part avec l'envoi ; une story les garde ; envoi enregistré avant : autorisés")
    func publication() async throws {
        let create = CreatePublicationUseCase(store: store, makeID: { "u1" })
        let upload = try create(file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "", userID: "a", commentsEnabled: false)
        #expect(!upload.commentsEnabled)
        let story = try create(
            file: store.addPickedFile("s.mov", Data("0123".utf8)), description: "", userID: "a", kind: .story, commentsEnabled: false)
        #expect(story.commentsEnabled)

        let use = UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: FakePartTransport(), store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.commentsEnabled(of: "vid-1") == false)

        let json = #"{"id":"u1","userID":"a","fileName":"f","contentType":"video/mp4","fileSize":1,"createdAt":0}"#
        #expect(try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8)).commentsEnabled)
    }

    @Test("couper : tout de suite à l'écran ; erreur : retour à l'état d'avant ; la vidéo d'un autre ne change pas")
    func toggle() async {
        let interactions = await makeInteractions()
        #expect(interactions.display(mine).commentsEnabled)
        #expect(await interactions.setCommentsEnabled(false, of: mine) == nil)
        #expect(!interactions.display(mine).commentsEnabled)
        #expect(videos.commentsEnabled(of: "v1") == false)

        videos.state.withLock { $0.visibilityError = .network }
        #expect(await interactions.setCommentsEnabled(true, of: mine) == AppError.network.message)
        #expect(!interactions.display(mine).commentsEnabled)

        #expect(await interactions.setCommentsEnabled(false, of: FeedVideo.sample("v2")) == nil)
        #expect(videos.commentsEnabled(of: "v2") == nil)
    }
}
