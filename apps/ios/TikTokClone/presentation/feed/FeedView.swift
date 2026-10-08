import AVFoundation
import SwiftUI

// Lecteur plein écran : une vidéo par page, défilement vertical natif (ScrollView en pagination).
// Le feed principal, le feed des abonnements (ADR-048), ou une liste ouverte depuis une grille (`allowsRefresh` faux).
struct FeedView: View {
    @State private var viewModel: FeedViewModel
    let pool: AVPlayerPool
    let interactions: VideoInteractionsModel
    let container: AppContainer
    let isTabActive: Bool
    let allowsRefresh: Bool
    let emptyState: FeedEmptyState
    @State private var scrolledID: String?
    @State private var commentsVideo: FeedVideo?
    @State private var shareVideo: FeedVideo?
    @State private var reportedVideo: FeedVideo?
    @State private var alertMessage: String?
    // Page d'un hashtag touché dans une description (ADR-049) : poussée par valeur dans la pile (`navigationPath`) ; à
    // défaut, par `navigationDestination(item:)`.
    @State private var hashtagRoute: HashtagRoute?
    // Feuille de cadeaux et animation à l'envoi (ADR-050).
    @State private var giftVideo: FeedVideo?
    @State private var giftBurst: GiftBurst?
    @Environment(\.navigationPath) private var navigationPath
    // Faux quand un autre écran est poussé par-dessus (profil, lecteur d'une grille).
    @State private var isOnScreen = false
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: FeedViewModel, pool: AVPlayerPool, interactions: VideoInteractionsModel, container: AppContainer, isTabActive: Bool,
        allowsRefresh: Bool = true, emptyState: FeedEmptyState = .feed
    ) {
        _viewModel = State(initialValue: viewModel)
        self.pool = pool
        self.interactions = interactions
        self.container = container
        self.isTabActive = isTabActive
        self.allowsRefresh = allowsRefresh
        self.emptyState = emptyState
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
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: isTabActive, initial: true) { updateActivity() }
        .onChange(of: isOnScreen) { updateActivity() }
        .onChange(of: scenePhase) { updateActivity() }
        .onChange(of: session.isSignedIn) { Task { await reload() } }
        .onChange(of: interactions.deletedVideoIDs) { _, ids in viewModel.remove(videoIDs: ids) }
        .onChange(of: interactions.blockedUserIDs) { _, ids in viewModel.remove(authorIDs: ids) }
        .videoInteractionSheets(
            comments: $commentsVideo, share: $shareVideo, report: $reportedVideo, alert: $alertMessage, interactions: interactions,
            container: container
        )
        .navigationDestination(item: $hashtagRoute) { route in
            HashtagView(viewModel: container.makeHashtagViewModel(name: route.name))
        }
        .giftSheet(video: $giftVideo, burst: $giftBurst, container: container)
    }

    // Cadeau (ADR-050) ; en invité, la connexion s'ouvre.
    private func openGifts(_ video: FeedVideo) {
        if session.isSignedIn { giftVideo = video } else { session.requestSignIn() }
    }

    private func reload() async {
        interactions.reset()
        await viewModel.reload()
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
                Button("Réessayer") { Task { await reload() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if viewModel.entries.isEmpty {
                ContentUnavailableView {
                    Label(emptyState.title, systemImage: emptyState.systemImage)
                } description: {
                    Text(emptyState.description)
                } actions: {
                    if let action = emptyState.action {
                        Button(action.title, action: action.run)
                            .buttonStyle(.borderedProminent)
                    }
                }
                // Tirer pour actualiser reste possible sur l'écran vide.
                .modifier(RefreshIfAllowed(isAllowed: allowsRefresh) { await reload() })
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
                        video: interactions.display(entry.video),
                        player: pool.player(for: entry.video.id),
                        showsPauseIndicator: entry.id == viewModel.currentEntryID && viewModel.isPaused,
                        bottomInset: bottomInset,
                        showsFollowButton: !interactions.isOwn(entry.video),
                        actions: .init(
                            interactions: interactions,
                            video: entry.video,
                            togglePause: { viewModel.togglePause() },
                            comments: { commentsVideo = interactions.display(entry.video) },
                            share: { shareVideo = interactions.display(entry.video) },
                            report: { report(entry.video) },
                            alert: { alertMessage = $0 },
                            openHashtag: { name in
                                if let navigationPath {
                                    navigationPath.wrappedValue.append(HashtagRoute(name: name))
                                } else {
                                    hashtagRoute = HashtagRoute(name: name)
                                }
                            },
                            gift: { openGifts(entry.video) },
                            // Avatar entouré de l'anneau (ADR-051) : ses stories, par-dessus le feed (mis en pause).
                            openStories: { container.router.openStories([entry.video.author], source: .feed) }
                        )
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(entry.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledID)
        .ignoresSafeArea()
        .modifier(RefreshIfAllowed(isAllowed: allowsRefresh) { await reload() })
        // Nouvelle ScrollView à chaque rechargement : elle repart en haut, sur la vidéo courante.
        .id(viewModel.reloadCount)
        .accessibilityIdentifier("feed.pages")
    }

    // « Signaler » (ADR-038) ; en invité, la connexion s'ouvre.
    private func report(_ video: FeedVideo) {
        if session.isSignedIn { reportedVideo = video } else { session.requestSignIn() }
    }

    private func updateActivity() {
        guard isTabActive && isOnScreen && scenePhase == .active else {
            viewModel.setActive(false)
            return
        }
        // Activé après les mises en pause du même changement (l'autre feed de l'accueil, une vidéo seule fermée) :
        // leur `pauseAll` arrêterait sinon la vidéo qui vient de démarrer. L'ordre des `onChange` de deux vues
        // sœurs n'est pas garanti.
        Task { @MainActor in viewModel.setActive(isTabActive && isOnScreen && scenePhase == .active) }
    }
}

// Écran d'un feed sans vidéo : celui du feed principal par défaut ; le feed des abonnements a le sien (ADR-048).
struct FeedEmptyState {
    struct Action {
        let title: String
        let run: () -> Void
    }

    let title: String
    let systemImage: String
    let description: String
    var action: Action?

    static var feed: FeedEmptyState {
        FeedEmptyState(title: "Aucune vidéo pour l’instant", systemImage: "play.rectangle", description: "Reviens un peu plus tard.")
    }
}

// Tirer pour actualiser : le feed seulement (une liste ouverte depuis une grille garde son ordre).
private struct RefreshIfAllowed: ViewModifier {
    let isAllowed: Bool
    let action: @Sendable () async -> Void

    func body(content: Content) -> some View {
        if isAllowed {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

// Actions d'une page vidéo, fournies par l'écran qui l'affiche (feed, vidéo seule).
struct VideoPageActions {
    var togglePause: () -> Void
    var doubleTapLike: () -> Void
    var toggle: (ReactionKind) -> Void
    var comments: () -> Void
    var share: () -> Void
    var follow: () -> Void
    // Menu « … » : celle d'un autre, « Signaler » (ADR-038) ; sa propre vidéo, « Supprimer », confirmé dans la colonne.
    var report: () -> Void
    var delete: () -> Void
    // Hashtag touché dans la description (ADR-049) : sa page.
    var openHashtag: (String) -> Void = { _ in }
    // Bouton 🎁 (ADR-050) : feuille de cadeaux, sur la vidéo d'un autre.
    var gift: () -> Void = {}
    // Avatar entouré de l'anneau des stories (ADR-051) : ses stories. Nil : l'avatar ouvre toujours le profil.
    var openStories: (() -> Void)? = nil
}

// Une page vidéo : miniature, puis vidéo dès que le lecteur est prêt ; auteur, description et boutons.
// Toucher : pause ou reprise ; double toucher : like, avec un cœur qui éclate à l'endroit touché.
struct FeedPageView: View {
    let video: FeedVideo
    let player: AVPlayer?
    let showsPauseIndicator: Bool
    let bottomInset: CGFloat
    let showsFollowButton: Bool
    let actions: VideoPageActions
    @State private var burst: HeartBurst?

    private struct HeartBurst: Identifiable, Equatable {
        let id = UUID()
        let location: CGPoint
    }

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
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).onEnded { value in
                    burst = HeartBurst(location: value.location)
                    actions.doubleTapLike()
                }
                .exclusively(before: TapGesture().onEnded { actions.togglePause() })
            )
            .overlay {
                if showsPauseIndicator {
                    Image(systemName: "play.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityLabel("En pause")
                }
            }
            .overlay(alignment: .topLeading) {
                if let burst {
                    HeartBurstView()
                        .position(burst.location)
                        .id(burst.id)
                        .allowsHitTesting(false)
                        .task(id: burst.id) {
                            try? await Task.sleep(for: .milliseconds(700))
                            if self.burst == burst { self.burst = nil }
                        }
                }
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink(value: ProfileRoute(username: video.author.username)) {
                            Text("@\(video.author.username)").font(.headline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("video.author")
                        if let description = video.description, !description.isEmpty {
                            // Hashtags cliquables (ADR-049) ; sans hashtag, le texte laisse passer les touchers.
                            HashtagText(text: description, onHashtag: actions.openHashtag)
                                .font(.subheadline).lineLimit(3)
                                .tint(.white)
                                .allowsHitTesting(!HashtagRules.occurrences(in: description).isEmpty)
                                .accessibilityIdentifier("video.description")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Lisible sur une vidéo claire.
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    FeedActionColumn(video: video, showsFollowButton: showsFollowButton, actions: actions)
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

// Cœur du double toucher : grossit puis s'efface.
struct HeartBurstView: View {
    @State private var isVisible = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 96))
            .foregroundStyle(.red.gradient)
            .shadow(radius: 10)
            .scaleEffect(isVisible ? 1 : 0.4)
            .opacity(isVisible ? 0 : 1)
            .rotationEffect(.degrees(isVisible ? -12 : 0))
            .onAppear {
                withAnimation(.spring(duration: 0.6)) { isVisible = true }
            }
            .accessibilityHidden(true)
    }
}

// Colonne de droite : auteur (avec « + » pour le suivre), puis like, commentaires, favori, republication, partage.
struct FeedActionColumn: View {
    let video: FeedVideo
    let showsFollowButton: Bool
    let actions: VideoPageActions
    // Confirmation attachée au menu : elle s'affiche à côté du bouton « … », pas dans un coin de l'écran.
    @State private var isConfirmingDelete = false
    @Environment(StoriesModel.self) private var stories: StoriesModel?

    var body: some View {
        let viewer = video.viewer ?? .empty
        // Anneau des stories de l'auteur (ADR-051) : ce que la visionneuse a vu ici l'emporte sur celui du feed.
        let ring = stories.map { $0.ring(for: video.author.id, fallback: video.authorStory) } ?? video.authorStory
        VStack(spacing: 18) {
            Group {
                if let ring, let openStories = actions.openStories {
                    Button(action: openStories) {
                        StoryAvatar(url: video.author.avatarURL, name: video.author.displayName, size: 44, ring: ring)
                    }
                    .accessibilityLabel("Stories de @\(video.author.username)")
                    .accessibilityIdentifier("video.authorStories")
                } else {
                    NavigationLink(value: ProfileRoute(username: video.author.username)) {
                        if let ring {
                            StoryAvatar(url: video.author.avatarURL, name: video.author.displayName, size: 44, ring: ring)
                        } else {
                            AvatarView(url: video.author.avatarURL, name: video.author.displayName, size: 48)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    .accessibilityLabel("Profil de @\(video.author.username)")
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                if showsFollowButton && !viewer.followingAuthor {
                    Button(action: actions.follow) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor, in: Circle())
                    }
                    .offset(y: 11)
                    .accessibilityLabel("Suivre @\(video.author.username)")
                    .accessibilityIdentifier("video.follow")
                }
            }
            .padding(.bottom, 6)
            FeedCounter(
                systemImage: "heart.fill", count: video.stats.likes, isActive: viewer.liked, activeColor: .red,
                label: viewer.liked ? "Je n’aime plus" : "J’aime"
            ) { actions.toggle(.like) }
            .accessibilityIdentifier("video.like")
            FeedCounter(systemImage: "ellipsis.bubble.fill", count: video.stats.comments, label: "Commentaires", action: actions.comments)
                .accessibilityIdentifier("video.comments")
            FeedCounter(
                systemImage: "bookmark.fill", count: video.stats.favorites, isActive: viewer.favorited, activeColor: .yellow,
                label: viewer.favorited ? "Retirer des favoris" : "Ajouter aux favoris"
            ) { actions.toggle(.favorite) }
            .accessibilityIdentifier("video.favorite")
            FeedCounter(
                systemImage: "arrow.2.squarepath", count: video.stats.reposts, isActive: viewer.reposted, activeColor: .green,
                label: viewer.reposted ? "Annuler la republication" : "Republier"
            ) { actions.toggle(.repost) }
            .accessibilityIdentifier("video.repost")
            FeedCounter(systemImage: "arrowshape.turn.up.right.fill", count: video.stats.shares, label: "Partager", action: actions.share)
                .accessibilityIdentifier("video.share")
            // Cadeau (ADR-050) : sur la vidéo d'un autre seulement. Aucun compteur : les cadeaux ne sont pas publics.
            if showsFollowButton {
                Button(action: actions.gift) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .frame(width: 56, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Offrir un cadeau")
                .accessibilityIdentifier("video.gift")
            }
            Menu {
                if showsFollowButton {
                    Button("Signaler", systemImage: "flag", role: .destructive, action: actions.report)
                } else {
                    Button("Supprimer la vidéo", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 24, weight: .bold))
                    .shadow(radius: 4)
                    .frame(width: 56, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsFollowButton ? "Plus d’options" : "Gérer la vidéo")
            .accessibilityIdentifier("video.manage")
            // Sa propre vidéo : suppression, quel que soit son statut (les autres écrans la retirent ensuite).
            .confirmationDialog("Supprimer cette vidéo ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive, action: actions.delete)
            } message: {
                Text("Ses likes, commentaires et republications disparaîtront aussi.")
            }
        }
    }
}

struct FeedCounter: View {
    let systemImage: String
    let count: Int
    var isActive = false
    var activeColor: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(isActive ? activeColor : .white)
                    .shadow(radius: 4)
                    .symbolEffect(.bounce, value: isActive)
                Text(count, format: .number.notation(.compactName))
                    .font(.caption.bold())
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .contentTransition(.numericText(value: Double(count)))
            }
            // Toute la zone du bouton est touchable : sinon un toucher entre l'icône et le compteur
            // passe à la vidéo dessous (pause).
            .frame(width: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: count)
        .accessibilityLabel(label)
        .accessibilityValue(Text(count, format: .number))
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
