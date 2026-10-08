import SwiftUI

// Vidéo seule en plein écran (lien d'app), fermée par le bouton natif de la barre d'outils.
struct VideoDetailView: View {
    @State private var viewModel: VideoDetailViewModel
    let pool: AVPlayerPool
    let interactions: VideoInteractionsModel
    let container: AppContainer
    @State private var commentsVideo: FeedVideo?
    @State private var shareVideo: FeedVideo?
    @State private var reportedVideo: FeedVideo?
    @State private var alertMessage: String?
    // Pile de la vidéo seule : une page de hashtag touché dans la description y est poussée (ADR-049).
    @State private var path = NavigationPath()
    // Feuille de cadeaux et animation à l'envoi (ADR-050).
    @State private var giftVideo: FeedVideo?
    @State private var giftBurst: GiftBurst?
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(viewModel: VideoDetailViewModel, pool: AVPlayerPool, interactions: VideoInteractionsModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.pool = pool
        self.interactions = interactions
        self.container = container
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                content(bottomInset: geometry.safeAreaInsets.bottom)
                    .ignoresSafeArea()
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("video.close")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear { viewModel.resume() }
            .onDisappear { viewModel.stop() }
            // Profils ouverts depuis la vidéo, dans la même pile.
            .appDestinations(container)
        }
        .providesNavigationPath($path)
        .giftSheet(video: $giftVideo, burst: $giftBurst, container: container)
        .environment(\.colorScheme, .dark)
        .task { await viewModel.start() }
        .onChange(of: interactions.deletedVideoIDs) { _, ids in
            if ids.contains(viewModel.videoID) { dismiss() }
        }
        // Auteur bloqué (profil ouvert depuis la vidéo) : la vidéo se ferme, comme une vidéo supprimée.
        .onChange(of: interactions.blockedUserIDs) { _, ids in
            if case .loaded(let video) = viewModel.state, ids.contains(video.author.id) { dismiss() }
        }
        .videoInteractionSheets(
            comments: $commentsVideo, share: $shareVideo, report: $reportedVideo, alert: $alertMessage, interactions: interactions,
            container: container
        )
        // Stories de l'auteur (ADR-051), présentées par-dessus la vidéo seule, mise en pause pendant ce temps.
        .storiesPresenter(container) { true }
        .onChange(of: container.router.presentedStories == nil) { _, closed in
            if closed { viewModel.resume() } else { viewModel.stop() }
        }
    }

    // « Signaler » (ADR-038) ; en invité, la connexion s'ouvre.
    private func report(_ video: FeedVideo) {
        if container.session.isSignedIn { reportedVideo = video } else { container.session.requestSignIn() }
    }

    @ViewBuilder
    private func content(bottomInset: CGFloat) -> some View {
        switch viewModel.state {
        case .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Vidéo indisponible", systemImage: "video.slash", description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let video):
            FeedPageView(
                video: interactions.display(video),
                player: pool.player(for: video.id),
                showsPauseIndicator: viewModel.isPaused,
                bottomInset: bottomInset,
                showsFollowButton: !interactions.isOwn(video),
                actions: .init(
                    interactions: interactions,
                    video: video,
                    togglePause: { viewModel.togglePause() },
                    comments: { commentsVideo = interactions.display(video) },
                    share: { shareVideo = interactions.display(video) },
                    report: { report(video) },
                    alert: { alertMessage = $0 },
                    openHashtag: { path.append(HashtagRoute(name: $0)) },
                    gift: { if session.isSignedIn { giftVideo = video } else { session.requestSignIn() } },
                    openStories: { container.router.openStories([video.author], source: .feed) }
                )
            )
        }
    }
}
