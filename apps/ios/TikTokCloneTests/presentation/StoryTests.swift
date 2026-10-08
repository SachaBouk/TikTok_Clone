import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Stories : visionneuse et rangée (ADR-051)")
struct StoryTests {
    let repository = FakeStoryRepository()
    let messaging = FakeMessagingRepository()
    let analytics = FakeAnalyticsService()

    func makeSession(signedIn: Bool = true) async -> SessionStore {
        let session = TikTokCloneTests.makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        return session
    }

    func makeModel(session: SessionStore) -> StoriesModel {
        StoriesModel(loadTray: LoadStoryTrayUseCase(stories: repository), loadStories: LoadUserStoriesUseCase(stories: repository), session: session)
    }

    func makeViewer(_ authors: [UserSummary], session: SessionStore, model: StoriesModel? = nil) -> (StoryViewerModel, StoriesModel) {
        let model = model ?? makeModel(session: session)
        let viewer = StoryViewerModel(
            authors: authors,
            source: .tray,
            loadStories: LoadUserStoriesUseCase(stories: repository),
            recordView: RecordStoryViewUseCase(stories: repository),
            setLiked: SetStoryLikedUseCase(stories: repository),
            deleteStory: DeleteStoryUseCase(stories: repository),
            reply: ReplyToStoryUseCase(messaging: messaging),
            model: model,
            session: session,
            analytics: makeAnalytics(analytics)
        )
        return (viewer, model)
    }

    static let carol = UserSummary(id: "carol-id", username: "carol", displayName: "Carol", avatarURL: nil)

    @Test("démarre à la première story pas encore vue, la marque vue ; 5 s par photo, puis la suivante et le compte suivant")
    func playback() async {
        repository.state.withLock {
            $0.stories["bob"] = [.sample("b1", viewed: true), .sample("b2"), .sample("b3")]
            $0.stories["carol"] = [.sample("c1", by: Self.carol)]
        }
        let (viewer, model) = makeViewer([.bob, Self.carol], session: await makeSession())
        await viewer.start()
        #expect(viewer.current?.id == "b2")
        #expect(viewer.current?.viewed == true)
        #expect(await eventually { repository.views == ["b2"] })

        viewer.tick(.seconds(2))
        #expect(abs(viewer.progress - 0.4) < 0.001)
        viewer.pause(.holding)
        viewer.tick(.seconds(4))
        #expect(viewer.current?.id == "b2")
        viewer.resume(.holding)
        viewer.tick(.seconds(3))
        #expect(viewer.current?.id == "b3")
        #expect(viewer.progress == 0)

        viewer.next()
        #expect(await eventually { viewer.current?.id == "c1" })
        // Toutes les stories de bob vues : son anneau passe au gris.
        #expect(model.ring(for: UserSummary.bob.id) == .seen)
        #expect(model.ring(for: Self.carol.id) == .seen)
        viewer.next()
        #expect(viewer.state == .finished)
        #expect(analytics.events.filter { $0.name == "story_viewed" }.count == 3)
    }

    @Test("précédente, compte sans story sauté, vidéo menée par le lecteur")
    func navigation() async {
        repository.state.withLock {
            $0.stories["bob"] = [.sample("b1", mediaType: .video)]
            $0.stories["carol"] = [.sample("c1", by: Self.carol), .sample("c2", by: Self.carol)]
        }
        let empty = UserSummary(id: "dave-id", username: "dave", displayName: "Dave", avatarURL: nil)
        let (viewer, _) = makeViewer([.bob, empty, Self.carol], session: await makeSession())
        await viewer.start()
        // Une vidéo n'avance pas à l'horloge des photos, mais selon le lecteur.
        viewer.tick(.seconds(10))
        #expect(viewer.current?.id == "b1")
        viewer.videoProgress(0.5)
        #expect(viewer.progress == 0.5)
        viewer.videoEnded()
        #expect(await eventually { viewer.current?.id == "c1" })
        viewer.next()
        #expect(viewer.current?.id == "c2")
        viewer.previous()
        #expect(viewer.current?.id == "c1")
    }

    @Test("invité : rien n'est marqué vu ; aimer et répondre ouvrent la connexion")
    func guest() async {
        repository.state.withLock { $0.stories["bob"] = [.sample("b1")] }
        let session = await makeSession(signedIn: false)
        let (viewer, _) = makeViewer([.bob], session: session)
        await viewer.start()
        #expect(viewer.current?.viewed == false)
        viewer.toggleLike()
        #expect(session.isPresentingSignIn)
        #expect(await viewer.sendReply("Salut") == false)
        #expect(repository.views.isEmpty)
        #expect(repository.likes.isEmpty)
    }

    @Test("like optimiste, annulé en cas d'erreur ; réponse par message envoyée")
    func likeAndReply() async {
        repository.state.withLock { $0.stories["bob"] = [.sample("b1")] }
        let (viewer, _) = makeViewer([.bob], session: await makeSession())
        await viewer.start()
        viewer.toggleLike()
        #expect(viewer.current?.liked == true)
        #expect(await eventually { repository.likes.count == 1 })

        repository.state.withLock { $0.likeError = .tooManyActions(.storyLikes, retryAfter: 30) }
        viewer.toggleLike()
        #expect(await eventually { viewer.current?.liked == true && viewer.notice != nil })

        #expect(await viewer.sendReply("Trop bien"))
        #expect(messaging.state.withLock { $0.repliedStoryIDs } == ["b1"])
        #expect(viewer.notice == "Message envoyé à @bob")
        #expect(analytics.events.contains { $0.name == "story_reply_sent" })
    }

    @Test("sa story : ni vue ni like ; suppression, puis fermeture quand il n'en reste plus")
    func ownStory() async {
        repository.state.withLock { $0.stories["alice"] = [.sample("a1", by: .alice, stats: StoryStats(viewers: 3, likes: 1))] }
        let (viewer, model) = makeViewer([.alice], session: await makeSession())
        await viewer.start()
        #expect(viewer.isOwn)
        viewer.toggleLike()
        #expect(repository.views.isEmpty && repository.likes.isEmpty)
        await viewer.deleteCurrent()
        #expect(repository.deleted == ["a1"])
        #expect(viewer.state == .finished)
        #expect(model.ring(for: UserSummary.alice.id) == nil)
    }

    @Test("rangée : sa story et celles des abonnements ; anneau de la rangée, du feed, puis du profil")
    func tray() async {
        repository.state.withLock {
            $0.tray = [
                StoryTrayEntry(user: .alice, storiesCount: 1, latestAt: .now, hasUnseen: false),
                StoryTrayEntry(user: .bob, storiesCount: 2, latestAt: .now, hasUnseen: true),
            ]
        }
        let model = makeModel(session: await makeSession())
        await model.refresh()
        #expect(model.ownEntry?.user == .alice)
        #expect(model.followedEntries.map(\.user) == [.bob])
        #expect(model.ring(for: UserSummary.bob.id) == .unseen)
        // Inconnu ici : l'anneau du feed sert.
        #expect(model.ring(for: Self.carol.id, fallback: .unseen) == .unseen)
        // Profil ouvert : plus de story (expirée) → plus d'anneau, même si le feed en montrait un.
        await model.loadRing(for: Self.carol)
        #expect(model.ring(for: Self.carol.id, fallback: .unseen) == nil)
        model.update(UserSummary.bob.id, stories: [.sample("b1", viewed: true)])
        #expect(model.followedEntries.first?.hasUnseen == false)
        model.reset()
        #expect(model.tray.isEmpty)
        #expect(model.ring(for: UserSummary.bob.id) == nil)
    }

    @Test("publication d'une story photo : publiée dès l'envoi, la rangée se relit")
    func publishStory() async {
        let store = InMemoryUploadStore()
        let videos = FakeVideoPublishingRepository()
        let session = await makeSession()
        let publishing = PublishingModel(
            createPublication: CreatePublicationUseCase(store: store),
            uploadVideo: UploadVideoUseCase(videos: videos, stories: repository, transport: FakePartTransport(), store: store, retryDelays: []),
            pendingUploads: PendingUploadsUseCase(store: store),
            cancelUpload: CancelUploadUseCase(videos: videos, stories: repository, store: store),
            loadPendingVideos: LoadPendingVideosUseCase(videos: videos),
            loadVideo: LoadOwnVideoUseCase(videos: videos),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            loadStory: LoadOwnStoryUseCase(stories: repository),
            deleteStory: DeleteStoryUseCase(stories: repository),
            session: session,
            analytics: makeAnalytics(analytics),
            makePreview: { _ in nil },
            beginBackgroundWork: { {} }
        )
        var published = 0
        publishing.onStoryPublished = { published += 1 }
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)),
            preparePhoto: PrepareStoryPhotoUseCase(renderer: FakeStoryPhotoRenderer(store: store)))
        draft.mode = .story
        await draft.loadMedia { .photo(Data("photo".utf8)) }
        #expect(draft.canPublish)
        #expect(draft.publish())
        #expect(await eventually { publishing.publications.first?.phase == .ready })
        #expect(publishing.publications.first?.kind == .story)
        #expect(published == 1)
        #expect(analytics.events.map(\.name).contains("story_published"))

        // En mode Vidéo, une photo est refusée ; une story vidéo trop longue aussi.
        draft.mode = .video
        await draft.loadMedia { .photo(Data("photo".utf8)) }
        #expect(draft.state == .failed("Choisis une vidéo."))
    }
}
