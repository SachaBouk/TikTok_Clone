import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Recherche : écran, historique, page d'un hashtag, suggestions (ADR-049)")
struct SearchTests {
    let repository = FakeSearchRepository()
    let interactionRepository = FakeInteractionRepository()
    let historyStore = InMemorySearchHistoryStore()

    func makeViewModel(signedIn: Bool = true) async -> (SearchViewModel, SearchHistoryModel, VideoInteractionsModel) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactionRepository),
            setFollow: SetFollowUseCase(interactions: interactionRepository),
            recordShare: ShareVideoUseCase(interactions: interactionRepository),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            session: session,
            analytics: makeAnalytics()
        )
        let history = SearchHistoryModel(store: historyStore)
        let viewModel = SearchViewModel(
            searchAccounts: SearchAccountsUseCase(search: repository),
            searchHashtags: SearchHashtagsUseCase(search: repository),
            loadTrending: LoadTrendingHashtagsUseCase(search: repository),
            history: history,
            interactions: interactions,
            session: session,
            debounce: .milliseconds(20)
        )
        return (viewModel, history, interactions)
    }

    @Test("saisie : une seule recherche après le délai de frappe ; hashtags puis comptes paginés")
    func debounce() async {
        repository.state.withLock { state in
            state.hashtags = [Hashtag(name: "lea", videosCount: 3)]
            state.accounts["lea"] = [
                AccountSearchPage(results: [.sample("lea"), .sample("lea.martin")], nextCursor: "1"),
                AccountSearchPage(results: [.sample("galea")], nextCursor: nil),
            ]
        }
        let (viewModel, _, _) = await makeViewModel()
        viewModel.text = "l"
        viewModel.text = "le"
        viewModel.text = "lea"
        try? await Task.sleep(for: .milliseconds(60))
        await viewModel.waitForSearch()
        #expect(repository.accountQueries == ["lea"])
        #expect(viewModel.hashtags.map(\.name) == ["lea"])
        #expect(viewModel.accounts?.items.map(\.user.username) == ["lea", "lea.martin"])
        await viewModel.accounts?.loadMore()
        #expect(viewModel.accounts?.items.map(\.user.username) == ["lea", "lea.martin", "galea"])

        // Champ vidé : retour à l'historique et aux tendances.
        viewModel.text = "  "
        #expect(!viewModel.isSearching)
        #expect(viewModel.accounts == nil)
        #expect(viewModel.hashtags.isEmpty)
    }

    @Test("« # » : hashtags seulement ; « @ » : comptes seulement")
    func prefixes() async {
        repository.state.withLock { $0.hashtags = [Hashtag(name: "plage", videosCount: 2)] }
        let (viewModel, _, _) = await makeViewModel()
        viewModel.text = "#pla"
        viewModel.submit()
        await viewModel.waitForSearch()
        #expect(viewModel.hashtags.map(\.name) == ["plage"])
        #expect(viewModel.accounts == nil)
        #expect(viewModel.completedQuery == "#pla")

        viewModel.text = "@lea"
        viewModel.submit()
        await viewModel.waitForSearch()
        #expect(repository.hashtagPrefixes == ["#pla"])
        #expect(repository.accountQueries == ["@lea"])
    }

    @Test("historique : validation et résultat ouvert retenus, recherche relancée depuis l'historique, effacé")
    func history() async {
        let (viewModel, history, _) = await makeViewModel()
        viewModel.text = "lea"
        viewModel.submit()
        await viewModel.waitForSearch()
        viewModel.text = "#plage"
        viewModel.resultOpened()
        #expect(history.queries == ["#plage", "lea"])
        #expect(historyStore.searchHistory == ["#plage", "lea"])

        viewModel.search(fromHistory: "lea")
        await viewModel.waitForSearch()
        #expect(viewModel.text == "lea")
        #expect(history.queries == ["lea", "#plage"])

        history.clear()
        #expect(historyStore.searchHistory.isEmpty)
        // Relu au lancement suivant.
        historyStore.setSearchHistory(["chat"])
        #expect(SearchHistoryModel(store: historyStore).queries == ["chat"])
    }

    @Test("tendances chargées une fois ; bouton d'abonnement, rien pour son compte ; compte bloqué retiré")
    func followAndBlock() async {
        repository.state.withLock { state in
            state.trending = [Hashtag(name: "été", videosCount: 10)]
            state.accounts["a"] = [
                AccountSearchPage(
                    results: [.sample("bob", viewer: FollowViewer(following: false, followedBy: true)), .sample("alice")], nextCursor: nil)
            ]
        }
        let (viewModel, _, interactions) = await makeViewModel()
        await viewModel.loadTrendingIfNeeded()
        #expect(viewModel.trending.map(\.name) == ["été"])
        viewModel.text = "a"
        viewModel.submit()
        await viewModel.waitForSearch()
        let bob = viewModel.accounts!.items[0]
        #expect(viewModel.status(of: bob) == .followBack)
        await viewModel.toggleFollow(bob)
        #expect(viewModel.status(of: bob) == .friends)
        #expect(interactionRepository.calls == ["follow-bob-true"])
        let alice = AccountSearchResult(user: .alice, followersCount: 0, viewer: nil)
        #expect(viewModel.status(of: alice) == nil)

        interactions.blocked("bob-id")
        viewModel.removeBlocked(viewModel.blockedUserIDs)
        #expect(viewModel.accounts?.items.map(\.user.username) == ["alice"])
    }

    @Test("page d'un hashtag : en-tête et grille ; vidéo supprimée retirée")
    func hashtagPage() async {
        repository.state.withLock { $0.hashtags = [Hashtag(name: "chat", videosCount: 2)] }
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let videoLists = FakeVideoListRepository()
        videoLists.set(.hashtag(name: "chat"), [page(["v1", "v2"], next: nil)])
        let publishing = FakeVideoPublishingRepository()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactionRepository),
            setFollow: SetFollowUseCase(interactions: interactionRepository),
            recordShare: ShareVideoUseCase(interactions: interactionRepository),
            deleteVideo: DeleteVideoUseCase(videos: publishing),
            session: session,
            analytics: makeAnalytics()
        )
        let viewModel = HashtagViewModel(
            name: "chat", loadHashtag: LoadHashtagUseCase(search: repository),
            loadVideos: LoadVideoListUseCase(videos: videoLists, list: .hashtag(name: "chat")), interactions: interactions, session: session)
        await viewModel.load()
        #expect(viewModel.title == "#chat")
        #expect(viewModel.hashtag == Hashtag(name: "chat", videosCount: 2))
        #expect(viewModel.videos.items.map(\.id) == ["v1", "v2"])
    }

    @Test("publication : suggestions pour le hashtag tapé à la fin, complétion")
    func publishSuggestions() async {
        repository.state.withLock { $0.hashtags = [Hashtag(name: "plage", videosCount: 4), Hashtag(name: "planche", videosCount: 1)] }
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let store = InMemoryUploadStore()
        let videos = FakeVideoPublishingRepository()
        let publishing = PublishingModel(
            createPublication: CreatePublicationUseCase(store: store),
            uploadVideo: UploadVideoUseCase(videos: videos, transport: FakePartTransport(), store: store, retryDelays: []),
            pendingUploads: PendingUploadsUseCase(store: store),
            cancelUpload: CancelUploadUseCase(videos: videos, store: store),
            loadPendingVideos: LoadPendingVideosUseCase(videos: videos),
            loadVideo: LoadOwnVideoUseCase(videos: videos),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            session: session,
            analytics: makeAnalytics(),
            makePreview: { _ in nil },
            beginBackgroundWork: { {} }
        )
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)),
            searchHashtags: SearchHashtagsUseCase(search: repository), suggestionDelay: .milliseconds(10),
            makePreview: { _ in nil }, loadDuration: { _ in nil })
        draft.description = "Au soleil #Pla"
        await draft.waitForSuggestions()
        #expect(repository.hashtagPrefixes == ["pla"])
        #expect(draft.hashtagSuggestions.map(\.name) == ["plage", "planche"])
        draft.applySuggestion(draft.hashtagSuggestions[0])
        #expect(draft.description == "Au soleil #plage ")
        #expect(draft.hashtagSuggestions.isEmpty)
        await draft.waitForSuggestions()
        // Hashtag terminé (espace) : plus rien à proposer.
        #expect(repository.hashtagPrefixes == ["pla"])

        draft.description = "Au soleil #plage"
        await draft.waitForSuggestions()
        #expect(draft.hashtagSuggestions.isEmpty)
    }
}
