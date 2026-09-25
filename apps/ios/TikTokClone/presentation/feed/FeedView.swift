import AVFoundation
import SwiftUI

// Feed plein écran : une vidéo par page, défilement vertical natif (ScrollView en pagination).
struct FeedView: View {
    @State private var viewModel: FeedViewModel
    let pool: AVPlayerPool
    let isTabActive: Bool
    @State private var scrolledID: String?
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: FeedViewModel, pool: AVPlayerPool, isTabActive: Bool) {
        _viewModel = State(initialValue: viewModel)
        self.pool = pool
        self.isTabActive = isTabActive
    }

    var body: some View {
        GeometryReader { geometry in
            content(bottomInset: geometry.safeAreaInsets.bottom, topInset: geometry.safeAreaInsets.top)
        }
        .background(.black)
        .environment(\.colorScheme, .dark)
        .task { await viewModel.start() }
        .onChange(of: viewModel.currentEntryID) { _, id in
            if scrolledID != id { scrolledID = id }
        }
        .onChange(of: scrolledID) { _, id in
            if let id, id != viewModel.currentEntryID { viewModel.show(id) }
        }
        .onChange(of: isTabActive, initial: true) { updateActivity() }
        .onChange(of: scenePhase) { updateActivity() }
        .onChange(of: session.isSignedIn) { Task { await viewModel.reload() } }
    }

    @ViewBuilder
    private func content(bottomInset: CGFloat, topInset: CGFloat) -> some View {
        switch viewModel.loadState {
        // Seul le chargement d'une première page passe par `.loading` (les pages suivantes se chargent en silence).
        case .idle, .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Feed indisponible", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await viewModel.reload() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if viewModel.entries.isEmpty {
                ContentUnavailableView("Aucune vidéo pour l’instant", systemImage: "play.rectangle", description: Text("Reviens un peu plus tard."))
            } else {
                pages(bottomInset: bottomInset, topInset: topInset)
            }
        }
    }

    private func pages(bottomInset: CGFloat, topInset: CGFloat) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.entries) { entry in
                    FeedPageView(
                        video: entry.video,
                        player: pool.player(for: entry.video.id),
                        showsPauseIndicator: entry.id == viewModel.currentEntryID && viewModel.isPaused,
                        bottomInset: bottomInset
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.togglePause() }
                    .id(entry.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledID)
        .ignoresSafeArea()
        .refreshable { await viewModel.reload() }
        // Nouvelle ScrollView à chaque rechargement : elle repart en haut, sur la vidéo courante.
        .id(viewModel.reloadCount)
        .accessibilityIdentifier("feed.pages")
    }

    private func updateActivity() {
        viewModel.setActive(isTabActive && scenePhase == .active)
    }
}

// Une page du feed : miniature, puis vidéo dès que le lecteur est prêt ; auteur, description et compteurs.
struct FeedPageView: View {
    let video: FeedVideo
    let player: AVPlayer?
    let showsPauseIndicator: Bool
    let bottomInset: CGFloat

    var body: some View {
        // La miniature et la vidéo sont en overlay : recadrées (scaledToFill), elles ne doivent pas agrandir la page.
        Color.black
            .overlay {
                AsyncImage(url: video.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
            }
            .overlay { PlayerLayerView(player: player) }
            .clipped()
            .overlay {
                if showsPauseIndicator {
                    Image(systemName: "play.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("En pause")
                }
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@\(video.author.username)").font(.headline)
                        if let description = video.description, !description.isEmpty {
                            Text(description).font(.subheadline).lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Lisible sur une vidéo claire.
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    FeedActionColumn(video: video)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset + 12)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 280 + bottomInset)
                        .allowsHitTesting(false)
                }
            }
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.15), value: showsPauseIndicator)
    }
}

// Colonne de droite : auteur et compteurs, avec l'état du compte connecté (cœur rempli…).
// En lecture seule pour l'instant ; les actions viendront avec les interactions.
struct FeedActionColumn: View {
    let video: FeedVideo

    var body: some View {
        VStack(spacing: 18) {
            AvatarView(url: video.author.avatarURL, name: video.author.displayName, size: 48)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            FeedCounter(systemImage: "heart.fill", count: video.stats.likes, isActive: video.viewer?.liked == true, activeColor: .red, label: "J’aime")
            FeedCounter(systemImage: "ellipsis.bubble.fill", count: video.stats.comments, label: "Commentaires")
            FeedCounter(systemImage: "bookmark.fill", count: video.stats.favorites, isActive: video.viewer?.favorited == true, activeColor: .yellow, label: "Favoris")
            FeedCounter(systemImage: "arrow.2.squarepath", count: video.stats.reposts, isActive: video.viewer?.reposted == true, activeColor: .green, label: "Republications")
            FeedCounter(systemImage: "arrowshape.turn.up.right.fill", count: video.stats.shares, label: "Partages")
        }
    }
}

struct FeedCounter: View {
    let systemImage: String
    let count: Int
    var isActive = false
    var activeColor: Color = .white
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(isActive ? activeColor : .white)
                .shadow(radius: 4)
            Text(count, format: .number.notation(.compactName))
                .font(.caption.bold())
                .shadow(color: .black.opacity(0.6), radius: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) : \(count)")
    }
}

// Couche AVPlayerLayer : la vidéo remplit l'écran (recadrée), transparente tant que rien n'est prêt.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) n'est pas utilisé")
        }
    }
}
