import SwiftUI

// Accueil : feed des abonnements (ADR-048) et feed principal (« Pour toi », ADR-016), choisis en haut de l'écran.
// - L'app s'ouvre toujours sur « Pour toi » (choix du développeur, comme TikTok).
// - Les deux feeds restent en place : chacun garde sa position quand on passe de l'un à l'autre.
// - Le feed des abonnements n'est chargé qu'à sa première ouverture, puis rechargé quand on y revient après un
//   abonnement ou un désabonnement fait dans l'app (`VideoInteractionsModel.followsVersion`), ou quand l'un d'eux
//   aboutit pendant qu'il est affiché. Il s'arrête à sa fin.
// - En invité, il invite à se connecter.
// - La loupe ouvre la recherche (ADR-049), dans la pile de l'accueil.
// - Toucher l'onglet Accueil alors qu'il est affiché recharge le feed affiché (comme TikTok) : les deux points rose et
//   cyan prennent la place de la loupe le temps du rechargement (0,8 s au moins).

struct HomeFeedView: View {
    enum Selection: Hashable {
        case following, forYou
    }

    let container: AppContainer
    // Onglet Accueil sélectionné, sans vidéo seule par-dessus.
    let isTabActive: Bool
    @State private var selection: Selection = .forYou
    @State private var forYou: FeedViewModel
    @State private var following: FeedViewModel?
    // `followsVersion` au dernier chargement du feed des abonnements.
    @State private var followingVersion = 0
    @Environment(SessionStore.self) private var session

    init(container: AppContainer, isTabActive: Bool) {
        self.container = container
        self.isTabActive = isTabActive
        _forYou = State(initialValue: container.makeFeedViewModel())
    }

    var body: some View {
        ZStack {
            feed(forYou, shown: selection == .forYou, emptyState: .feed, showsSwipeHint: true, showsSuggestionCarousel: true)
            if !session.isSignedIn {
                if selection == .following { guestPrompt }
            } else if let following {
                feed(following, shown: selection == .following, emptyState: followingEmptyState)
            }
        }
        .background(.black)
        .overlay(alignment: .top) {
            FeedSelector(selection: $selection).opacity(barOpacity)
                .accessibilityHidden(barOpacity == 0)
                // Lus avant les vidéos (ADR-076) : sinon VoiceOver les atteint après tout le feed.
                .accessibilitySortPriority(3)
        }
        // Live commun (ADR-079) : lives en cours de toutes les apps membres. Le serveur commun exige un compte connecté.
        .overlay(alignment: .topLeading) {
            Button {
                if container.session.isSignedIn {
                    container.router.openLiveFeed()
                } else {
                    container.session.requestSignIn(message: "Connecte-toi pour regarder et lancer des lives.")
                }
            } label: {
                LiveIcon()
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel("Lives")
            .accessibilityIdentifier("feed.lives")
            .opacity(barOpacity)
            .accessibilityHidden(barOpacity == 0)
            .accessibilitySortPriority(4)
        }
        // Recherche de comptes et hashtags (ADR-049).
        .overlay(alignment: .topTrailing) {
            Group {
                if container.router.isHomeRefreshing {
                    DotsLoader(size: 10)
                        .frame(width: 44, height: 36)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityIdentifier("feed.refreshing")
                        .onAppear { Accessibility.announce("Actualisation du feed") }
                } else {
                    NavigationLink(value: SearchRoute()) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Rechercher")
                    .accessibilityIdentifier("feed.search")
                }
            }
            .padding(.trailing, 8)
            .opacity(barOpacity)
            .accessibilityHidden(barOpacity == 0)
            .accessibilitySortPriority(2)
        }
        .animation(.easeInOut(duration: 0.15), value: barOpacity)
        // Conteneur : les priorités ci-dessus mettent « Lives », le sélecteur et la loupe avant les vidéos (ADR-076).
        .accessibilityElement(children: .contain)
        // Affichage allégé (ADR-067) : sans barre d'onglets ; les barres du haut ne se touchent plus.
        .toolbarVisibility(container.playbackOptions.isClearMode ? .hidden : .automatic, for: .tabBar)
        .onChange(of: container.router.homeRefreshRequests) { Task { await refreshShownFeed() } }
        .onChange(of: selection) { showFollowingIfSelected() }
        // Abonnement confirmé par l'API alors que le feed des abonnements est déjà affiché (toucher « Abonnements »
        // pendant l'envoi, désabonnement depuis un profil ouvert par-dessus).
        .onChange(of: container.videoInteractions.followsVersion) { showFollowingIfSelected() }
        .onChange(of: session.isSignedIn) { _, isSignedIn in
            // Un autre compte se connectera peut-être : son feed des abonnements repartira de zéro.
            if !isSignedIn { following = nil }
            // Changement de session : toujours sur « Pour toi », comme à l'ouverture.
            selection = .forYou
            showFollowingIfSelected()
        }
    }

    // Pendant l'appui long de la vitesse ×2 et en affichage allégé (ADR-067) : sélecteur, « LIVE » et loupe masqués,
    // seule la vidéo reste.
    private var barOpacity: Double {
        let options = container.playbackOptions
        // Balayage vers le profil d'un auteur : la barre ne passe pas par-dessus le profil qui arrive.
        return options.isHolding || options.isClearMode || container.router.isSwipingToProfile ? 0 : 1
    }

    private func feed(
        _ viewModel: FeedViewModel, shown: Bool, emptyState: FeedEmptyState, showsSwipeHint: Bool = false, showsSuggestionCarousel: Bool = false
    ) -> some View {
        FeedView(
            viewModel: viewModel,
            pool: container.playerPool,
            interactions: container.videoInteractions,
            container: container,
            isTabActive: isTabActive && shown,
            emptyState: emptyState,
            showsSwipeHint: showsSwipeHint,
            showsSuggestionCarousel: showsSuggestionCarousel
        )
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }

    // Recharge le feed affiché (« Pour toi », ou les abonnements), une fois à la fois.
    private func refreshShownFeed() async {
        let router = container.router
        guard !router.isHomeRefreshing else { return }
        let viewModel: FeedViewModel? = selection == .forYou ? forYou : following
        guard let viewModel else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { router.isHomeRefreshing = true }
        async let minimum: Void = { try? await Task.sleep(for: Self.refreshMinimumDuration) }()
        await viewModel.reload()
        await minimum
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { router.isHomeRefreshing = false }
    }

    // La flèche et les points restent au moins ce temps (environ un tour de flèche, comme sur la vidéo de TikTok).
    static let refreshMinimumDuration: Duration = .milliseconds(800)

    private func showFollowingIfSelected() {
        guard selection == .following, session.isSignedIn else { return }
        let version = container.videoInteractions.followsVersion
        if following == nil {
            following = container.makeFollowingFeedViewModel()
            followingVersion = version
        } else if followingVersion != version, let following {
            followingVersion = version
            Task { await following.reload() }
        }
    }

    private var followingEmptyState: FeedEmptyState {
        let followsNobody = session.profile?.followingCount == 0
        return FeedEmptyState(
            title: followsNobody ? "Tu ne suis personne pour l’instant" : "Aucune vidéo de tes abonnements",
            systemImage: "person.2",
            description: followsNobody
                ? "Suis des comptes depuis « Pour toi » pour retrouver ici leurs vidéos."
                : "Les comptes que tu suis n’ont encore rien publié.",
            action: .init(title: "Découvrir « Pour toi »") { selection = .forYou }
        )
    }

    private var guestPrompt: some View {
        ContentUnavailableView {
            Label("Abonnements", systemImage: "person.2")
        } description: {
            Text("Connecte-toi pour voir les vidéos des comptes que tu suis.")
        } actions: {
            Button("Se connecter") { session.requestSignIn() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("following.signIn")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }
}

// « Abonnements | Pour toi », en haut du feed, lisible sur une vidéo claire.
private struct FeedSelector: View {
    @Binding var selection: HomeFeedView.Selection

    var body: some View {
        HStack(spacing: 24) {
            item("Abonnements", .following, identifier: "feed.tab.following")
            item("Pour toi", .forYou, identifier: "feed.tab.forYou")
        }
        .padding(.top, 6)
    }

    private func item(_ title: String, _ value: HomeFeedView.Selection, identifier: String) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                Capsule()
                    .fill(.white)
                    .frame(width: 24, height: 3)
                    .opacity(isSelected ? 1 : 0)
            }
            .shadow(color: .black.opacity(0.6), radius: 3)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .animation(.snappy, value: isSelected)
    }
}

// Icône « LIVE » de l'accueil (ADR-066, ouvre le Live commun de l'ADR-079), comme celle de TikTok : un cadre aux coins arrondis, ouvert sur les côtés
// autour de « LIVE », et une antenne en V posée sur le bord du haut.
struct LiveIcon: View {
    private static let width: CGFloat = 30
    private static let height: CGFloat = 24
    private static let antenna: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            LiveIconFrame()
                .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: Self.width, height: Self.height + Self.antenna)
            Text("LIVE")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(-0.2)
                .foregroundStyle(.white)
                .frame(width: Self.width + 4, height: Self.height)
                .offset(y: Self.antenna)
        }
        .frame(width: Self.width + 4, height: Self.height + Self.antenna)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
}

// Tracé de l'icône « LIVE » : antenne en V, haut et bas du cadre avec des bouts de côtés (le texte occupe le milieu).
private struct LiveIconFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let antenna: CGFloat = 6
        let radius: CGFloat = 5
        let side: CGFloat = 4
        let top = rect.minY + antenna
        let bottom = rect.maxY
        var path = Path()
        // Antenne : deux traits qui se rejoignent sur le bord du haut.
        path.move(to: CGPoint(x: rect.midX - 5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: top))
        path.addLine(to: CGPoint(x: rect.midX + 5, y: rect.minY))
        // Haut du cadre.
        path.move(to: CGPoint(x: rect.minX, y: top + radius + side))
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: top), control: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + radius), control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top + radius + side))
        // Bas du cadre.
        path.move(to: CGPoint(x: rect.minX, y: bottom - radius - side))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: bottom), control: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bottom - radius), control: CGPoint(x: rect.maxX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - radius - side))
        return path
    }
}
