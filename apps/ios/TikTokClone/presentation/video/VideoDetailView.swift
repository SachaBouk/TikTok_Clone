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
    // Menu de la vidéo (ADR-067).
    @State private var menuVideo: FeedVideo?
    // Vidéo horizontale en plein écran, en paysage.
    @State private var fullScreenVideo: FeedVideo?
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
            stackRoot
                // Profils ouverts depuis la vidéo, dans la même pile.
                .appDestinations(container)
        }
        .providesNavigationPath($path)
        .giftSheet(video: $giftVideo, burst: $giftBurst, container: container)
        .landscapePlayer(video: $fullScreenVideo, content: landscapePlayer)
        .environment(\.colorScheme, .dark)
        .task { await viewModel.start() }
        .onChange(of: interactions.deletedVideoIDs) { _, ids in
            if ids.contains(viewModel.videoID) { dismiss() }
        }
        // Auteur bloqué (profil ouvert depuis la vidéo) : la vidéo se ferme, comme une vidéo supprimée.
        .onChange(of: interactions.blockedUserIDs) { _, ids in
            if case .loaded(let video) = viewModel.state, ids.contains(video.author.id) { dismiss() }
        }
        // Vidéo signalée : voile par-dessus, lecture arrêtée jusqu'à « Afficher la vidéo ».
        .onChange(of: interactions.reportedVideoIDs.contains(viewModel.videoID), initial: true) { _, masked in
            viewModel.setMasked(masked)
        }
        .videoInteractionSheets(
            comments: $commentsVideo, share: $shareVideo, report: $reportedVideo, alert: $alertMessage, menu: $menuVideo,
            interactions: interactions, container: container
        )
        // « Pas intéressé(e) » (ADR-067) : la vidéo seule se ferme.
        .onChange(of: interactions.notInterestedVideoIDs) { _, ids in
            if ids.contains(viewModel.videoID) { dismiss() }
        }
        // Stories de l'auteur (ADR-051), présentées par-dessus la vidéo seule, mise en pause pendant ce temps.
        .storiesPresenter(container) { true }
        .onChange(of: container.router.presentedStories == nil) { _, closed in
            if closed { viewModel.resume() } else { viewModel.stop() }
        }
    }

    // Racine de la pile : la page de la vidéo, ses bandeaux et sa barre d'outils.
    private var stackRoot: some View {
        GeometryReader { geometry in
            content(bottomInset: geometry.safeAreaInsets.bottom)
                .ignoresSafeArea()
        }
        .background(.black)
        // Balayage vers la gauche : profil de l'auteur, poussé dans la pile de la vidéo seule.
        .authorProfileSwipe(author: swipeAuthor, container: container, open: openAuthorProfile)
        // Vitesse ×2 : bandeau en bas pendant l'appui, message du verrouillage en haut.
        .overlay { FastPlaybackBottomBar(model: container.playbackOptions) }
        .overlay { VideoDownloadOverlay(model: container.downloads) }
        .overlay(alignment: .top) {
            FastPlaybackNoticeView(model: container.playbackOptions).padding(.top, 12)
        }
        .toolbar {
            // Masqué pendant l'appui long de la vitesse ×2, l'affichage allégé et le balayage vers le profil.
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("video.close")
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { viewModel.resume() }
        .onDisappear {
            viewModel.stop()
            // Affichage allégé (ADR-067) : quitté avec la vidéo seule.
            container.playbackOptions.setClearMode(false)
        }
    }

    // Plein écran en paysage de la vidéo (horizontale).
    private func landscapePlayer(_ video: FeedVideo, close: @escaping () -> Void) -> some View {
        LandscapePlayerView(
            loadedVideo: video,
            player: pool.player(for: video.id),
            isPaused: viewModel.isPaused,
            actions: .init(
                togglePause: { viewModel.togglePause() },
                progress: { pool.progress(of: video.id) },
                seek: { pool.seek(video.id, to: $0) },
                close: close
            ),
            options: container.playbackOptions, interactions: interactions, container: container
        )
    }

    private var showsCloseButton: Bool {
        let options = container.playbackOptions
        return !options.isHolding && !options.isClearMode && !container.router.isSwipingToProfile
    }

    private func openAuthorProfile(_ author: UserSummary) {
        path.append(ProfileRoute(username: author.username))
    }

    private var swipeAuthor: UserSummary? {
        let options = container.playbackOptions
        guard path.isEmpty, container.router.presentedStories == nil, !options.isHolding, !options.isClearMode, !options.isScrubbing,
            case .loaded(let video) = viewModel.state
        else { return nil }
        return video.author
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
                showsPauseIndicator: viewModel.isPaused && !viewModel.isMasked,
                bottomInset: bottomInset,
                showsFollowButton: !interactions.isOwn(video),
                actions: .init(
                    interactions: interactions,
                    video: video,
                    togglePause: { viewModel.togglePause() },
                    comments: { commentsVideo = interactions.display(video) },
                    share: { shareVideo = interactions.display(video) },
                    alert: { alertMessage = $0 },
                    openHashtag: { path.append(HashtagRoute(name: $0)) },
                    openMention: { path.append(ProfileRoute(username: $0)) },
                    gift: { if session.isSignedIn { giftVideo = video } else { session.requestSignIn() } },
                    openStories: { container.router.openStories([video.author], source: .feed) },
                    openMenu: { menuVideo = interactions.display(video) }
                ),
                progress: { pool.progress(of: video.id) },
                revealReported: viewModel.isMasked ? { interactions.showReported(videoID: video.id) } : nil,
                options: container.playbackOptions,
                seek: { pool.seek(video.id, to: $0) },
                scrubbing: { pool.setScrubbing($0, videoID: video.id) },
                // Plein écran : seulement quand la vidéo est affichée (pas sous une page poussée ni des stories).
                openFullScreen: path.isEmpty && container.router.presentedStories == nil
                    ? { withoutAnimation { fullScreenVideo = video } } : nil
            )
        }
    }
}
