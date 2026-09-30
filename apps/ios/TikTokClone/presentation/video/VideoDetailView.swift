import SwiftUI

// Vidéo seule en plein écran (lien d'app), fermée par le bouton natif de la barre d'outils.
struct VideoDetailView: View {
    @State private var viewModel: VideoDetailViewModel
    let pool: AVPlayerPool
    let interactions: VideoInteractionsModel
    let container: AppContainer
    @State private var commentsVideo: FeedVideo?
    @State private var shareVideo: FeedVideo?
    @State private var manageVideo: FeedVideo?
    @State private var alertMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: VideoDetailViewModel, pool: AVPlayerPool, interactions: VideoInteractionsModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.pool = pool
        self.interactions = interactions
        self.container = container
    }

    var body: some View {
        NavigationStack {
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
        .environment(\.colorScheme, .dark)
        .task { await viewModel.start() }
        .onChange(of: interactions.deletedVideoIDs) { _, ids in
            if ids.contains(viewModel.videoID) { dismiss() }
        }
        // Auteur bloqué (profil ouvert depuis la vidéo) : la vidéo se ferme, comme une vidéo supprimée.
        .onChange(of: interactions.blockedUserIDs) { _, ids in
            if case .loaded(let video) = viewModel.state, ids.contains(video.author.id) { dismiss() }
        }
        .videoInteractionSheets(comments: $commentsVideo, share: $shareVideo, manage: $manageVideo, alert: $alertMessage, interactions: interactions, container: container)
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
                    manage: { manageVideo = video },
                    alert: { alertMessage = $0 }
                )
            )
        }
    }
}
