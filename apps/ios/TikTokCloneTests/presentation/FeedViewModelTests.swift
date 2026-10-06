import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("FeedViewModel")
struct FeedViewModelTests {
    let playback = FakePlayback()
    let history = FakeViewHistoryRepository()

    func makeViewModel(_ pages: [Result<FeedPage, AppError>], signedIn: Bool = true) async -> (FeedViewModel, FakeFeedRepository) {
        let feed = FakeFeedRepository(pages)
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        let viewModel = FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: feed),
            recordView: RecordViewUseCase(history: history),
            playback: playback,
            session: session,
            analytics: makeAnalytics(),
            viewDelay: .milliseconds(20)
        )
        return (viewModel, feed)
    }

    func waitForViewDelay() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    @Test("premier affichage : lit la première vidéo et précharge la suivante")
    func start() async {
        let (viewModel, feed) = await makeViewModel([.success(page(["a", "b", "c", "d", "e"], next: "c1"))])
        await viewModel.start()
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.currentVideo?.id == "a")
        #expect(playback.loaded.last == ["a", "b"])
        #expect(playback.played == ["a"])
        #expect(feed.requestedCursors == [nil])
    }

    @Test("défilement : lit la nouvelle vidéo, garde la précédente et la suivante, libère le reste")
    func scroll() async {
        let (viewModel, _) = await makeViewModel([.success(page(["a", "b", "c", "d", "e", "f", "g", "h"], next: "c1"))])
        await viewModel.start()
        viewModel.show(viewModel.entries[2].id)
        #expect(playback.loaded.last == ["c", "d", "b"])
        #expect(playback.played.last == "c")
    }

    @Test("pages suivantes avec le curseur ; fin de session : nouvelle session, entrées distinctes")
    func pagination() async {
        let (viewModel, feed) = await makeViewModel([
            .success(page(["a", "b"], next: "c1")),
            .success(page(["c"], next: nil)),
            .success(page(["b", "a"], next: "c2")),
        ])
        await viewModel.start()
        await viewModel.loadMore()
        await viewModel.loadMore()
        #expect(feed.requestedCursors == [nil, "c1", nil])
        #expect(viewModel.entries.map(\.video.id) == ["a", "b", "c", "b", "a"])
        #expect(Set(viewModel.entries.map(\.id)).count == 5)
        // La fin de session ne recrée pas la ScrollView (les vidéos s'ajoutent à la suite).
        #expect(viewModel.reloadCount == 0)
    }

    @Test("feed des abonnements (ADR-048) : pages suivantes, puis arrêt à la fin, sans nouvelle session")
    func followingFeed() async {
        let feed = FakeFeedRepository([.success(page(["a", "b"], next: "c1")), .success(page(["c"], next: nil))])
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let viewModel = FeedViewModel(
            loadPage: LoadFollowingFeedPageUseCase(feed: feed), recordView: RecordViewUseCase(history: history),
            playback: playback, session: session, analytics: makeAnalytics(), mode: .followingFeed, viewDelay: .milliseconds(20))
        await viewModel.start()
        await viewModel.loadMore()
        await viewModel.loadMore()
        #expect(feed.requestedFeeds == ["following", "following"])
        #expect(feed.requestedCursors == [nil, "c1"])
        #expect(viewModel.entries.map(\.video.id) == ["a", "b", "c"])

        // Tirer pour actualiser : depuis la plus récente.
        await viewModel.reload()
        #expect(feed.requestedCursors == [nil, "c1", nil])
    }

    @Test("vue enregistrée après le délai de lecture, une seule fois par vidéo")
    func recordsView() async throws {
        let (viewModel, _) = await makeViewModel([.success(page(["a", "b"], next: nil))])
        await viewModel.start()
        try await waitForViewDelay()
        #expect(history.recorded == ["a"])
        viewModel.show(viewModel.entries[1].id)
        try await waitForViewDelay()
        viewModel.show(viewModel.entries[0].id)
        try await waitForViewDelay()
        #expect(history.recorded == ["a", "b"])
    }

    @Test("pas de vue si la vidéo est quittée ou mise en pause avant le délai")
    func noViewIfLeft() async throws {
        let (viewModel, _) = await makeViewModel([.success(page(["a", "b", "c"], next: nil))])
        await viewModel.start()
        viewModel.show(viewModel.entries[1].id)
        viewModel.togglePause()
        try await waitForViewDelay()
        #expect(history.recorded.isEmpty)
    }

    @Test("mode invité : aucune vue envoyée")
    func guestNoView() async throws {
        let (viewModel, _) = await makeViewModel([.success(page(["a"], next: nil))], signedIn: false)
        await viewModel.start()
        try await waitForViewDelay()
        #expect(history.recorded.isEmpty)
    }

    @Test("pause et reprise au toucher ; onglet quitté puis retrouvé")
    func pauseAndActivity() async {
        let (viewModel, _) = await makeViewModel([.success(page(["a", "b"], next: nil))])
        await viewModel.start()
        viewModel.togglePause()
        #expect(viewModel.isPaused)
        #expect(playback.pauseCount == 1)
        viewModel.togglePause()
        #expect(playback.played == ["a", "a"])

        viewModel.setActive(false)
        #expect(playback.pauseCount == 2)
        viewModel.setActive(true)
        #expect(playback.played == ["a", "a", "a"])
    }

    @Test("échec du premier chargement, puis réessai")
    func failureThenRetry() async {
        let (viewModel, _) = await makeViewModel([.failure(.network), .success(page(["a"], next: nil))])
        await viewModel.start()
        #expect(viewModel.loadState == .failed(AppError.network.message))
        await viewModel.reload()
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.currentVideo?.id == "a")
        // Rechargement : première vidéo courante, et la vue repart en haut.
        #expect(viewModel.currentEntryID == viewModel.entries.first?.id)
        #expect(viewModel.reloadCount == 1)
    }

    @Test("session expirée à l'envoi d'une vue : retour en invité")
    func sessionExpiredOnView() async throws {
        history.fail(with: .sessionExpired)
        let feed = FakeFeedRepository([.success(page(["a"], next: nil))])
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let viewModel = FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: feed), recordView: RecordViewUseCase(history: history),
            playback: playback, session: session, analytics: makeAnalytics(), viewDelay: .milliseconds(20))
        await viewModel.start()
        try await waitForViewDelay()
        #expect(!session.isSignedIn)
        #expect(session.notice != nil)
    }
}
