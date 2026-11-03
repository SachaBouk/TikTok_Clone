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
    // Mention touchée dans une description, sans pile de navigation fournie (ADR-065).
    @State private var mentionRoute: ProfileRoute?
    // Feuille de cadeaux et animation à l'envoi (ADR-050).
    @State private var giftVideo: FeedVideo?
    @State private var giftBurst: GiftBurst?
    // Menu de la vidéo (ADR-067), ouvert par un appui long au milieu.
    @State private var menuVideo: FeedVideo?
    // Vidéo horizontale en plein écran, en paysage.
    @State private var fullScreenVideo: FeedVideo?
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
        // Message du verrouillage de la vitesse ×2 ou du défilement automatique, sous la barre du haut.
        .overlay(alignment: .top) {
            FastPlaybackNoticeView(model: container.playbackOptions)
                .padding(.top, 66)
        }
        // Téléchargement d'une vidéo dans Photos (ADR-067).
        .overlay { VideoDownloadOverlay(model: container.downloads) }
        .background(.black)
        .environment(\.colorScheme, .dark)
        // Balayage vers la gauche : profil de l'auteur de la vidéo affichée (pas pendant le ×2 ni l'affichage allégé).
        .authorProfileSwipe(author: swipeAuthor, container: container) { openProfile($0.username) }
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
        // « Pas intéressé(e) » (ADR-067) : la vidéo quitte le lecteur, la suivante devient courante.
        .onChange(of: interactions.notInterestedVideoIDs) { _, ids in viewModel.remove(videoIDs: ids) }
        // Défilement automatique (ADR-067) : à la fin de la vidéo courante, la suivante ; jamais sous une feuille ouverte
        // (menu, commentaires, partage, signalement, cadeaux), qui porte sur la vidéo affichée.
        .onChange(of: pool.lastLoopEnd) { _, end in
            let sheetOpen =
                menuVideo != nil || commentsVideo != nil || shareVideo != nil || reportedVideo != nil || giftVideo != nil
                || fullScreenVideo != nil
            guard let end, container.playbackOptions.autoScroll, !sheetOpen, let next = viewModel.entryAfterEnd(of: end.videoID)
            else { return }
            withAnimation(.easeInOut(duration: 0.35)) { scrolledID = next }
        }
        // Affichage allégé (ADR-067) : quitté en quittant le lecteur (autre onglet, écran poussé par-dessus).
        .onChange(of: isTabActive && isOnScreen) { wasShown, isShown in
            if wasShown && !isShown { container.playbackOptions.setClearMode(false) }
        }
        // Vidéo signalée : voile par-dessus, lecture arrêtée jusqu'à « Afficher la vidéo ».
        .onChange(of: interactions.reportedVideoIDs, initial: true) { _, ids in viewModel.setMasked(ids) }
        .videoInteractionSheets(
            comments: $commentsVideo, share: $shareVideo, report: $reportedVideo, alert: $alertMessage, menu: $menuVideo,
            interactions: interactions, container: container
        )
        .navigationDestination(item: $hashtagRoute) { route in
            HashtagView(viewModel: container.makeHashtagViewModel(name: route.name))
        }
        .navigationDestination(item: $mentionRoute) { route in
            ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
        }
        .giftSheet(video: $giftVideo, burst: $giftBurst, container: container)
        .landscapePlayer(video: $fullScreenVideo) { video, close in
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
                            openMention: { openProfile($0) },
                            gift: { openGifts(entry.video) },
                            // Avatar entouré de l'anneau (ADR-051) : ses stories, par-dessus le feed (mis en pause).
                            openStories: { container.router.openStories([entry.video.author], source: .feed) },
                            openMenu: { menuVideo = interactions.display(entry.video) }
                        ),
                        // Barre de progression : la vidéo courante seulement.
                        progress: entry.id == viewModel.currentEntryID ? { pool.progress(of: entry.video.id) } : nil,
                        revealReported: interactions.reportedVideoIDs.contains(entry.video.id)
                            ? { interactions.showReported(videoID: entry.video.id) } : nil,
                        options: container.playbackOptions,
                        seek: { pool.seek(entry.video.id, to: $0) },
                        scrubbing: { pool.setScrubbing($0, videoID: entry.video.id) },
                        openFullScreen: entry.id == viewModel.currentEntryID && isTabActive && isOnScreen
                            ? { withoutAnimation { fullScreenVideo = entry.video } } : nil
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

    private var swipeAuthor: UserSummary? {
        let options = container.playbackOptions
        guard isTabActive, isOnScreen, !options.isHolding, !options.isClearMode, !options.isScrubbing, let video = viewModel.currentVideo
        else { return nil }
        return video.author
    }

    // Profil poussé dans la pile de l'écran (mention touchée, balayage vers la gauche).
    private func openProfile(_ username: String) {
        if let navigationPath {
            navigationPath.wrappedValue.append(ProfileRoute(username: username))
        } else {
            mentionRoute = ProfileRoute(username: username)
        }
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
    // Mention touchée dans la description (ADR-065) : le profil.
    var openMention: (String) -> Void = { _ in }
    // Bouton 🎁 (ADR-050) : feuille de cadeaux, sur la vidéo d'un autre.
    var gift: () -> Void = {}
    // Avatar entouré de l'anneau des stories (ADR-051) : ses stories. Nil : l'avatar ouvre toujours le profil.
    var openStories: (() -> Void)? = nil
    // Appui long au milieu de la vidéo (ADR-067) : menu de la vidéo.
    var openMenu: () -> Void = {}
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
    // Vitesse ×2 à l'appui long sur un côté (`FastPlayback`) ; nil : pas d'appui long.
    var options: PlaybackOptionsModel? = nil
    // Barre de progression de l'affichage allégé (ADR-067) : déplace la lecture (fraction de la vidéo).
    var seek: ((Double) -> Void)? = nil
    // Début et fin d'un glissement sur la barre de progression (lecture suspendue pendant ce temps).
    var scrubbing: ((Bool) -> Void)? = nil
    // Plein écran en paysage d'une vidéo horizontale : bouton sous la vidéo, ou iPhone tourné. Nil : la page n'est pas
    // celle qu'on regarde (autre page, feed caché ou recouvert).
    var openFullScreen: (() -> Void)? = nil
    @State private var burst: HeartBurst?
    @State private var width: CGFloat = 0
    // Taille affichée de la vidéo, lue sur le lecteur (zéro tant qu'elle n'est pas prête).
    @State private var videoSize = CGSize.zero
    // Doigt posé sur la barre de progression : position visée (fraction de la vidéo) ; nil sinon.
    @State private var scrubFraction: Double?

    private var offersFullScreen: Bool { VideoFraming.offersFullScreen(width: videoSize.width, height: videoSize.height) }

    // Pendant l'appui long, et en affichage allégé (ADR-067) : seule la vidéo reste, comme TikTok.
    private var hidesOverlays: Bool { options?.isHolding == true || options?.isClearMode == true || scrubFraction != nil }

    private struct HeartBurst: Identifiable, Equatable {
        let id = UUID()
        let location: CGPoint
    }

    var body: some View {
        // La miniature et la vidéo sont en overlay : recadrées (scaledToFill), elles ne doivent pas agrandir la page.
        // Cadrées selon leur format (`VideoFraming`) : une vidéo carrée ou horizontale est montrée entière.
        Color.black
            .overlay {
                FramedThumbnail(url: video.thumbnailURL) { Color.black }
            }
            .overlay { PlayerLayerView(player: player, adaptsToVideo: true, onVideoSize: { videoSize = $0 }) }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).onEnded { value in
                    burst = HeartBurst(location: value.location)
                    actions.doubleTapLike()
                }
                .exclusively(before: TapGesture().onEnded { actions.togglePause() })
            )
            .modifier(
                FastPlaybackGestureIfAvailable(
                    model: options, width: width, bottomInset: bottomInset, isEnabled: revealReported == nil,
                    allowsFast: !showsPauseIndicator, openMenu: actions.openMenu)
            )
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
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
            .overlay {
                // « Plein écran » juste sous la vidéo horizontale, montrée entière au centre de la page.
                if openFullScreen != nil, offersFullScreen, !hidesOverlays, revealReported == nil {
                    GeometryReader { geometry in
                        let videoHeight = min(geometry.size.height, geometry.size.width * videoSize.height / videoSize.width)
                        FullScreenButton { openFullScreen?() }
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + videoHeight / 2 + 34)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let tilt = DeviceTilt(UIDevice.current.orientation)
                if let openFullScreen, LandscapeRotation.entersFullScreen(tilt: tilt, offersFullScreen: offersFullScreen, isCurrent: true) {
                    openFullScreen()
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
                .opacity(hidesOverlays ? 0 : 1)
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    // Un peu au-dessus de la barre d'onglets, qui la touchait. Le doigt posé dessus avance ou recule dans
                    // la vidéo (zone de 30 pt autour de la barre) ; le reste disparaît, le temps visé s'affiche en grand.
                    let scrubbing = scrubFraction != nil
                    PlaybackProgressBar(progress: progress, isPaused: showsPauseIndicator, scrubFraction: scrubFraction)
                        .padding(.vertical, Self.scrubTouchMargin)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture, isEnabled: seek != nil && revealReported == nil && options?.isHolding != true)
                        // Barre de 18 pt (place du gros point) : 6 pt plus bas, la ligne reste où elle était.
                        .padding(.bottom, bottomInset + Self.progressBarGap - Self.scrubTouchMargin - 6)
                        .opacity(hidesOverlays && !scrubbing ? 0 : 1)
                        .accessibilityIdentifier("feed.progress")
                }
            }
            .overlay(alignment: .bottom) {
                if let scrubFraction, let progress {
                    let labels = PlaybackScrub.labels(fraction: scrubFraction, duration: progress()?.duration)
                    HStack(spacing: 22) {
                        Text(labels.position).foregroundStyle(.white)
                        Text("/").foregroundStyle(.white.opacity(0.6))
                        Text(labels.duration).foregroundStyle(.white.opacity(0.6))
                    }
                    .font(.system(size: 44, weight: .semibold).monospacedDigit())
                    .shadow(color: .black.opacity(0.35), radius: 4)
                    .padding(.bottom, bottomInset + 90)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("feed.scrubTime")
                }
            }
            .overlay(alignment: .bottom) {
                // Affichage allégé (ADR-067) : la vidéo courante a sa barre de lecture en bas.
                if let options, options.isClearMode, !options.isHolding, let progress {
                    ClearModeBar(
                        progress: progress, isPaused: showsPauseIndicator, speed: options.speed, bottomInset: bottomInset,
                        seek: { seek?($0) }, togglePause: actions.togglePause,
                        cycleSpeed: { options.setSpeed(options.speed.next) }, close: { options.setClearMode(false) }
                    )
                    .transition(.opacity)
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
            .animation(.easeInOut(duration: 0.15), value: hidesOverlays)
            .animation(.easeInOut(duration: 0.2), value: options?.isClearMode)
    }

    // Espace entre la barre de progression et la barre d'onglets.
    static let progressBarGap: CGFloat = 8
    // Marge tactile au-dessus et au-dessous de la barre de progression.
    static let scrubTouchMargin: CGFloat = 12

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrubFraction == nil {
                    options?.isScrubbing = true
                    scrubbing?(true)
                }
                let inset = PlaybackProgressBar.scrubInset
                let fraction = PlaybackScrub.fraction(x: value.location.x - inset, width: width - 2 * inset)
                scrubFraction = fraction
                seek?(fraction)
            }
            .onEnded { _ in
                scrubFraction = nil
                options?.isScrubbing = false
                scrubbing?(false)
            }
    }

    // Pseudo et description, avec une ombre pour rester lisibles sur une vidéo claire.
    private var authorAndDescription: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Lieu (ADR-065) : pastille au-dessus du pseudo ; pas encore de page d'un lieu.
            if let location = video.location {
                Label(location.name, systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: Capsule())
                    .accessibilityLabel("Lieu : \(location.name)")
                    .accessibilityIdentifier("video.location")
            }
            NavigationLink(value: ProfileRoute(username: video.author.username)) {
                Text("@\(video.author.username)").font(.headline)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("video.author")
            if let description = video.description, !description.isEmpty {
                // Hashtags et mentions cliquables (ADR-049, ADR-065) ; sans lien, le texte laisse passer les touchers.
                HashtagText(text: description, onHashtag: actions.openHashtag, onMention: actions.openMention)
                    .font(.subheadline).lineLimit(3)
                    .tint(.white)
                    .allowsHitTesting(HashtagText.hasLinks(description, mentions: true))
                    .accessibilityIdentifier("video.description")
            }
            // Étiquette « Contenu généré par l'IA » (ADR-065).
            if video.aiGenerated {
                Label("Créé avec l’IA", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: Capsule())
                    .accessibilityIdentifier("video.aiGenerated")
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
    }
}

// Appui long de la vitesse ×2, sur les pages qui en ont un modèle.
private struct FastPlaybackGestureIfAvailable: ViewModifier {
    let model: PlaybackOptionsModel?
    let width: CGFloat
    let bottomInset: CGFloat
    let isEnabled: Bool
    let allowsFast: Bool
    let openMenu: () -> Void

    func body(content: Content) -> some View {
        if let model {
            content.gesture(
                FastPlaybackGesture(
                    model: model, width: width, bottomInset: bottomInset, isEnabled: isEnabled, allowsFast: allowsFast, openMenu: openMenu))
        } else {
            content
        }
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
    // Doigt posé sur la barre : position visée, barre épaisse et gros point, comme TikTok ; nil : lecture.
    var scrubFraction: Double? = nil

    // Marges de la barre épaisse pendant le glissement.
    static let scrubInset: CGFloat = 14

    var body: some View {
        TimelineView(.animation(paused: isPaused || scrubFraction != nil)) { _ in
            let fraction = scrubFraction ?? progress()?.fraction ?? 0
            let scrubbing = scrubFraction != nil
            let line: CGFloat = scrubbing ? 8 : 2
            let dot: CGFloat = scrubbing ? 18 : 6
            GeometryReader { geometry in
                let x = geometry.size.width * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: line)
                    Capsule().fill(.white.opacity(0.9)).frame(width: x, height: line)
                    Circle().fill(.white).frame(width: dot, height: dot)
                        .offset(x: min(max(0, x - dot / 2), geometry.size.width - dot))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            .padding(.horizontal, scrubbing ? Self.scrubInset : 0)
        }
        .animation(.easeOut(duration: 0.15), value: scrubFraction == nil)
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
    // Vrai : le cadrage suit le format de la vidéo (`VideoFraming`), lu sur l'élément en cours ; `fills` est ignoré.
    var adaptsToVideo = false
    // Taille affichée de la vidéo, dès qu'elle est connue (bouton « Plein écran » d'une vidéo horizontale).
    var onVideoSize: ((CGSize) -> Void)? = nil

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.adaptsToVideo = adaptsToVideo
        view.prefersFill = fills
        view.onVideoSize = onVideoSize
        if view.playerLayer.player !== player { view.attach(player) }
        view.applyGravity()
    }

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var adaptsToVideo = false
        var prefersFill = true
        var onVideoSize: ((CGSize) -> Void)?
        // Taille affichée de l'élément en cours (rotation comprise), zéro tant qu'il n'est pas prêt.
        private var videoSize = CGSize.zero
        private var itemObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?

        // Le lecteur bouclé (`AVPlayerLooper`) change d'élément à chaque tour : la taille est relue sur chacun.
        func attach(_ player: AVPlayer?) {
            playerLayer.player = player
            // Lecteur déjà prêt (vidéo voisine préchargée) : sa taille est connue tout de suite, la vidéo arrive cadrée
            // (sinon elle remplissait l'écran le temps d'une image, puis se resserrait).
            videoSize = player?.currentItem?.presentationSize ?? .zero
            if videoSize != .zero {
                let size = videoSize
                Task { @MainActor in self.onVideoSize?(size) }
            }
            sizeObservation = nil
            itemObservation = player?.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.observeCurrentItemSize() }
            }
        }

        private func observeCurrentItemSize() {
            sizeObservation = playerLayer.player?.currentItem?.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
                let size = item.presentationSize
                Task { @MainActor in
                    guard let self, size != .zero, size != self.videoSize else { return }
                    self.videoSize = size
                    self.applyGravity()
                    self.onVideoSize?(size)
                }
            }
        }

        func applyGravity() {
            let fills = adaptsToVideo ? VideoFraming.fills(width: videoSize.width, height: videoSize.height) : prefersFill
            let gravity: AVLayerVideoGravity = fills ? .resizeAspectFill : .resizeAspect
            guard playerLayer.videoGravity != gravity else { return }
            // Sans animation : la couche animerait le changement, et la vidéo paraîtrait étirée le temps de la transition.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.videoGravity = gravity
            CATransaction.commit()
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
            // Les touchers passent à la page dessous : sinon l'appui long de la vitesse ×2 (reconnaisseur d'UIKit) ne
            // les reçoit pas.
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) n'est pas utilisé")
        }
    }
}
