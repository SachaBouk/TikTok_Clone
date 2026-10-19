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
    // « Pour toi » : indication « Balaie vers le haut » sur la première vidéo, une fois par installation (ADR-055).
    let showsSwipeHint: Bool
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
        allowsRefresh: Bool = true, emptyState: FeedEmptyState = .feed, showsSwipeHint: Bool = false
    ) {
        _viewModel = State(initialValue: viewModel)
        self.pool = pool
        self.interactions = interactions
        self.container = container
        self.isTabActive = isTabActive
        self.allowsRefresh = allowsRefresh
        self.emptyState = emptyState
        self.showsSwipeHint = showsSwipeHint
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
            if let id, id != viewModel.currentEntryID {
                viewModel.show(id)
                if showsSwipeHint { container.onboarding.feedSwipeHintSeen() }
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: isTabActive, initial: true) { updateActivity() }
        .onChange(of: isOnScreen) { updateActivity() }
        .onChange(of: scenePhase) { updateActivity() }
        .onChange(of: session.isSignedIn) { Task { await reload() } }
        .onChange(of: interactions.deletedVideoIDs) { _, ids in viewModel.remove(videoIDs: ids) }
        .onChange(of: interactions.blockedUserIDs) { _, ids in viewModel.remove(authorIDs: ids) }
        // Vidéo signalée : voile par-dessus, lecture arrêtée jusqu'à « Afficher la vidéo ».
        .onChange(of: interactions.reportedVideoIDs, initial: true) { _, ids in viewModel.setMasked(ids) }
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
                        showsPauseIndicator: entry.id == viewModel.currentEntryID && viewModel.isPaused
                            && !interactions.reportedVideoIDs.contains(entry.video.id),
                        bottomInset: bottomInset,
                        showsFollowButton: !interactions.isOwn(entry.video),
                        actions: .init(
                            interactions: interactions,
                            video: entry.video,
                            togglePause: { viewModel.togglePause() },
                            comments: { commentsVideo = interactions.display(entry.video) },
                            share: { shareVideo = interactions.display(entry.video) },
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
                        ),
                        // Barre de progression : la vidéo courante seulement.
                        progress: entry.id == viewModel.currentEntryID ? { pool.progress(of: entry.video.id) } : nil,
                        revealReported: interactions.reportedVideoIDs.contains(entry.video.id)
                            ? { interactions.showReported(videoID: entry.video.id) } : nil
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
        .overlay {
            // Au-dessus des pages, sous l'onboarding : attend la fin de celui-ci pour être vue.
            if showsSwipeHint, container.onboarding.showsFeedSwipeHint, isTabActive, !container.onboarding.isPresented {
                FeedSwipeHint { container.onboarding.feedSwipeHintSeen() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: container.onboarding.showsFeedSwipeHint)
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
    // Hashtag touché dans la description (ADR-049) : sa page.
    var openHashtag: (String) -> Void = { _ in }
    // Bouton 🎁 (ADR-050) : feuille de cadeaux, sur la vidéo d'un autre.
    var gift: () -> Void = {}
    // Avatar entouré de l'anneau des stories (ADR-051) : ses stories. Nil : l'avatar ouvre toujours le profil.
    var openStories: (() -> Void)? = nil
}

// Une page vidéo : miniature, puis vidéo dès que le lecteur est prêt ; pastille de republication, auteur, description
// et boutons ; fine barre de progression tout en bas, au-dessus de la barre d'onglets.
// Toucher : pause ou reprise ; double toucher : like, avec un cœur qui éclate à l'endroit touché.
struct FeedPageView: View {
    let video: FeedVideo
    let player: AVPlayer?
    let showsPauseIndicator: Bool
    let bottomInset: CGFloat
    let showsFollowButton: Bool
    let actions: VideoPageActions
    // Position de lecture, lue à chaque image tant que la vidéo joue ; nil : pas de barre (page qui n'est pas la courante).
    var progress: (() -> PlaybackProgress?)? = nil
    // Vidéo signalée (ADR-038) : voile « Merci pour ton signalement » par-dessus toute la page ; l'action l'enlève
    // (« Afficher la vidéo »). Nil : pas de voile.
    var revealReported: (() -> Void)? = nil
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
                // Grand triangle « lecture » semi-transparent, comme TikTok.
                if showsPauseIndicator {
                    Image(systemName: "play.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.5))
                        .shadow(color: .black.opacity(0.2), radius: 6)
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
                    VStack(alignment: .leading, spacing: 10) {
                        // Pastille sans ombre (fond blanc plein) : seul le texte en dessous en a une.
                        if let badge = RepostBadge.of(video, isOwn: !showsFollowButton) {
                            RepostPill(badge: badge, toggle: { actions.toggle(.repost) })
                        }
                        // Sa vidéo privée (ADR-061) : seul lui la voit.
                        if video.visibility == .onlyMe {
                            Label("Toi uniquement", systemImage: "lock.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(.white.opacity(0.92), in: Capsule())
                                .accessibilityIdentifier("video.private")
                        }
                        authorAndDescription
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    FeedActionColumn(video: video, showsFollowButton: showsFollowButton, actions: actions)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset + Self.progressBarGap + 14)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 280 + bottomInset)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    // Un peu au-dessus de la barre d'onglets, qui la touchait.
                    PlaybackProgressBar(progress: progress, isPaused: showsPauseIndicator)
                        .padding(.bottom, bottomInset + Self.progressBarGap)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if let revealReported {
                    ReportedVideoMask(bottomInset: bottomInset, reveal: revealReported)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.15), value: showsPauseIndicator)
            .animation(.easeInOut(duration: 0.25), value: revealReported == nil)
    }

    // Espace entre la barre de progression et la barre d'onglets.
    static let progressBarGap: CGFloat = 8

    // Pseudo et description, avec une ombre pour rester lisibles sur une vidéo claire.
    private var authorAndDescription: some View {
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
        .shadow(color: .black.opacity(0.6), radius: 3)
    }
}

// Voile d'une vidéo signalée, comme TikTok : la vidéo (arrêtée sur son image) reste devinée sous un flou sombre, coche
// verte dans un rond gris, « Merci pour ton signalement », puis « Afficher la vidéo ». Il recouvre auteur, description et
// boutons, et retient les touchers (pas de pause ni de like) ; le défilement vers la vidéo suivante reste possible.
struct ReportedVideoMask: View {
    let bottomInset: CGFloat
    let reveal: () -> Void

    var body: some View {
        // Flou d'UIKit : celui de SwiftUI (`blur`) ne s'applique pas à la couche du lecteur (AVPlayerLayer).
        BlurView(style: .systemUltraThinMaterialDark)
            // Assombri un peu, pour que le texte blanc reste lisible sur une vidéo claire.
            .overlay { Color.black.opacity(0.2) }
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color(red: 0.13, green: 0.85, blue: 0.6))
                        .frame(width: 78, height: 78)
                        .background(.white.opacity(0.15), in: Circle())
                    Text("Merci pour ton signalement")
                        .font(.title3.bold())
                        .padding(.top, 22)
                    Text("Pour améliorer ton expérience, cette vidéo a été masquée.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    Button(action: reveal) {
                        Text("Afficher la vidéo")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 96)
                    .accessibilityIdentifier("video.showReported")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, bottomInset)
            }
            .contentShape(Rectangle())
            // Retient les touchers de la page dessous (pause, double toucher).
            .onTapGesture {}
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("video.reportedMask")
    }
}

// Flou d'UIKit par-dessus ce qui est dessous (vidéo comprise).
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: style)
    }
}

// Pastille blanche au-dessus du pseudo (`RepostBadge`) : « Republier » republie au toucher ; « Tu as republié » (avec
// la photo du compte connecté) propose de retirer la republication, confirmation attachée à la pastille.
struct RepostPill: View {
    let badge: RepostBadge
    let toggle: () -> Void
    @State private var isConfirmingRemoval = false
    @Environment(SessionStore.self) private var session: SessionStore?

    var body: some View {
        Button {
            if badge == .reposted { isConfirmingRemoval = true } else { toggle() }
        } label: {
            HStack(spacing: 6) {
                switch badge {
                case .repost:
                    Image(systemName: "arrow.2.squarepath").font(.system(size: 13, weight: .semibold))
                    Text("Republier")
                case .reposted:
                    if let profile = session?.profile {
                        AvatarView(url: profile.avatarURL, name: profile.displayName, size: 20)
                    }
                    Text("Tu as republié")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.leading, badge == .reposted && session?.profile != nil ? 3 : 10)
            .padding(.trailing, 10)
            .frame(height: 26)
            .background(.white.opacity(0.92), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge == .reposted ? "Tu as republié, retirer la republication" : "Republier")
        .accessibilityIdentifier("video.repost")
        .confirmationDialog("Retirer la republication ?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Retirer", role: .destructive, action: toggle)
        } message: {
            Text("La vidéo disparaîtra de tes republications.")
        }
    }
}

// Fine barre de progression de la lecture, avec un point à la position courante. Relue à chaque image tant que la
// vidéo joue, figée en pause.
struct PlaybackProgressBar: View {
    let progress: () -> PlaybackProgress?
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { _ in
            let fraction = progress()?.fraction ?? 0
            GeometryReader { geometry in
                let x = geometry.size.width * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 2)
                    Capsule().fill(.white.opacity(0.9)).frame(width: x, height: 2)
                    Circle().fill(.white).frame(width: 6, height: 6).offset(x: min(max(0, x - 3), geometry.size.width - 6))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 6)
        }
        .accessibilityHidden(true)
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

// Colonne de droite, comme TikTok : auteur (avec « + » rouge pour le suivre), puis like (rouge une fois aimée),
// commentaires, favori (jaune une fois enregistrée), partage, cadeau. La republication est la pastille en bas à gauche ;
// signaler ou supprimer sa vidéo passent par la feuille de partage (`VideoShareSheet`).
struct FeedActionColumn: View {
    let video: FeedVideo
    let showsFollowButton: Bool
    let actions: VideoPageActions
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
                if showsFollowButton {
                    FollowPlusButton(isFollowing: viewer.followingAuthor, username: video.author.username, follow: actions.follow)
                        .offset(y: 11)
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
        }
    }
}

// « + » rose sous l'avatar de l'auteur, comme TikTok : au toucher, il rétrécit, un rond blanc avec une coche rose grandit
// à sa place, reste un instant, puis rétrécit jusqu'à disparaître (choix du développeur, d'après une vidéo de TikTok).
// Un abonnement fait ailleurs (profil, liste) le retire sans animation ; un abonnement refusé (erreur, blocage) remet le
// « + ». Avec « Réduire les animations » : fondus seulement.
struct FollowPlusButton: View {
    let isFollowing: Bool
    let username: String
    let follow: () -> Void

    private enum Phase {
        case idle
        case confirming
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.idle
    @State private var plusScale: CGFloat = 1
    @State private var checkScale: CGFloat = 0
    @State private var showsCheck = false

    // Durées relevées sur la vidéo de TikTok.
    static let shrink: Duration = .milliseconds(80)
    static let hold: Duration = .milliseconds(750)
    static let vanish: Duration = .milliseconds(120)

    var body: some View {
        ZStack {
            if showsCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.brandPink)
                    .frame(width: 22, height: 22)
                    .background(.white, in: Circle())
                    .scaleEffect(checkScale)
                    .opacity(reduceMotion ? checkScale : 1)
                    // Même cadre que le « + » (et sa zone touchable) : la coche prend exactement sa place.
                    .padding(6)
                    .accessibilityLabel("Abonné(e) à @\(username)")
            } else if !isFollowing || phase == .confirming {
                Button {
                    guard phase == .idle else { return }
                    follow()
                    Task { await confirm() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.brandPink, in: Circle())
                        .scaleEffect(plusScale)
                        .opacity(reduceMotion ? plusScale : 1)
                        // Zone touchable plus grande que la pastille de 22 pt.
                        .padding(6)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suivre @\(username)")
                .accessibilityIdentifier("video.follow")
            }
        }
        .padding(-6)
        // Abonnement refusé pendant l'animation, ou désabonnement ailleurs : le « + » revient, entier.
        .onChange(of: isFollowing) { _, following in
            if !following, phase == .idle { plusScale = 1 }
        }
    }

    private func confirm() async {
        phase = .confirming
        withAnimation(.easeIn(duration: Self.shrink.seconds)) { plusScale = 0 }
        try? await Task.sleep(for: Self.shrink)
        showsCheck = true
        checkScale = 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.22, dampingFraction: 0.6)) { checkScale = 1 }
        try? await Task.sleep(for: Self.hold)
        withAnimation(.easeIn(duration: Self.vanish.seconds)) { checkScale = 0 }
        try? await Task.sleep(for: Self.vanish)
        showsCheck = false
        phase = .idle
        // Abonnement refusé entre-temps : le « + » réapparaît.
        plusScale = 1
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
    // Faux : la vidéo est ajustée (bandes noires) au lieu de remplir le cadre.
    var fills = true

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        let gravity: AVLayerVideoGravity = fills ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
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
