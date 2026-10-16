import SwiftUI

// Barre d'onglets native. En invité, seul l'accueil est accessible ; les autres onglets proposent de se connecter.
struct MainTabView: View {
    enum Destination: Hashable {
        case home, friends, publish, inbox, profile
    }

    let container: AppContainer
    @Environment(SessionStore.self) private var session
    @State private var selection: Destination = .home
    // Écrans poussés au-dessus du feed (profils, lecteur d'une grille) : le feed se met en pause.
    @State private var feedPath = NavigationPath()
    // Chemins des autres onglets : une page de hashtag y est poussée par valeur (ADR-049).
    @State private var friendsPath = NavigationPath()
    @State private var inboxPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    // Icône de l'onglet Accueil pendant un rechargement (flèche qui tourne, `HomeTabIcon`).
    @State private var homeIcon = HomeTabIcon.standard
    @State private var homeIconTask: Task<Void, Never>?
    private var router: AppRouter { container.router }

    // Toucher l'onglet déjà sélectionné : Accueil revient au feed s'il y a des écrans par-dessus, sinon le recharge
    // (comme TikTok).
    private var tabSelection: Binding<Destination> {
        Binding(
            get: { selection },
            set: { new in
                if new == .home, selection == .home {
                    if feedPath.isEmpty { container.router.homeRefreshRequests += 1 } else { feedPath = NavigationPath() }
                }
                selection = new
            }
        )
    }

    // Étapes de l'icône d'Accueil, ~30 par seconde, jusqu'au retour de la maison après le rechargement.
    private func animateHomeIcon() async {
        let start = Date.now
        var end: Date?
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(start)
            if end == nil, !container.router.isHomeRefreshing, HomeTabIcon.canEnd(elapsed: elapsed) { end = .now }
            let icon = HomeTabIcon.at(elapsed: elapsed, endedFor: end.map { Date.now.timeIntervalSince($0) })
            homeIcon = icon
            if icon == .standard { return }
            try? await Task.sleep(for: HomeTabIcon.frameInterval)
        }
    }

    var body: some View {
        @Bindable var session = session
        @Bindable var router = container.router
        TabView(selection: tabSelection) {
            Tab(value: .home) {
                NavigationStack(path: $feedPath) {
                    // « Abonnements | Pour toi » (ADR-048).
                    HomeFeedView(
                        container: container,
                        // En pause pendant qu'une vidéo seule est ouverte par-dessus.
                        isTabActive: selection == .home && !router.coversTabs
                    )
                    .toolbar(.hidden, for: .navigationBar)
                    .appDestinations(container)
                }
                .providesNavigationPath($feedPath)
                .environment(\.isTabActive, selection == .home && !router.coversTabs)
            } label: {
                // Pendant le rechargement demandé par un toucher sur l'onglet : une flèche qui tourne, comme TikTok.
                Label {
                    Text("Accueil")
                } icon: {
                    switch homeIcon {
                    case .standard: Image(systemName: "house")
                    case .frame(let symbol, let angle, let scale): Image(uiImage: HomeTabIcon.image(symbol: symbol, angle: angle, scale: scale))
                    }
                }
            }
            // Feed des amis (ADR-054), entre l'accueil et la publication.
            Tab("Amis", systemImage: "person.2", value: .friends) {
                SignedInOnly(title: "Amis", systemImage: "person.2", reason: "Connecte-toi pour voir les vidéos de tes amis.") {
                    NavigationStack(path: $friendsPath) {
                        FriendsFeedView(container: container, isTabActive: selection == .friends && !router.coversTabs) {
                            selection = .home
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .appDestinations(container)
                    }
                    .providesNavigationPath($friendsPath)
                    .environment(\.isTabActive, selection == .friends && !router.coversTabs)
                }
            }
            Tab("Publier", systemImage: "plus.app", value: .publish) {
                SignedInOnly(title: "Publier", systemImage: "plus.app", reason: "Connecte-toi pour publier une vidéo.") {
                    PublishView(
                        draft: container.makePublishDraftViewModel(), publishing: container.publishing, router: container.router, container: container
                    )
                }
            }
            // Publications en cours d'envoi ou de traitement.
            .badge(container.publishing.inProgressCount)
            // Onglet « Messages » (ADR-058, ex-« Boîte de réception ») : activité et conversations.
            Tab("Messages", systemImage: "message", value: .inbox) {
                SignedInOnly(title: "Messages", systemImage: "message", reason: "Connecte-toi pour voir tes messages et ton activité.") {
                    NavigationStack(path: $inboxPath) {
                        InboxView(container: container)
                            .appDestinations(container)
                    }
                    .providesNavigationPath($inboxPath)
                    .environment(\.isTabActive, selection == .inbox && !router.coversTabs)
                }
            }
            // Notifications non lues, conversations non lues et demandes reçues.
            .badge(container.inboxBadgeCount)
            Tab("Profil", systemImage: "person", value: .profile) {
                SignedInOnly(
                    title: "Profil", systemImage: "person.crop.circle", reason: "Connecte-toi pour créer ton profil et suivre des comptes.",
                    showsPrivacy: true
                ) {
                    NavigationStack(path: $profilePath) {
                        ProfileView(viewModel: container.makeProfileViewModel(username: nil), container: container)
                            .appDestinations(container)
                    }
                    .providesNavigationPath($profilePath)
                    .environment(\.isTabActive, selection == .profile && !router.coversTabs)
                }
            }
        }
        // Menu ☰ de son profil (ADR-057) : par-dessus la barre d'onglets ; une ligne pousse sa page dans le profil.
        .overlay {
            ProfileMenuOverlay(isOpen: $router.isProfileMenuOpen) { route in profilePath.append(route) }
        }
        .onChange(of: selection) { router.isProfileMenuOpen = false }
        .onChange(of: router.isHomeRefreshing) { _, refreshing in
            guard refreshing else { return }
            homeIconTask?.cancel()
            homeIconTask = Task { await animateHomeIcon() }
        }
        .onChange(of: session.isSignedIn) { router.isProfileMenuOpen = false }
        .sheet(isPresented: $session.isPresentingSignIn) {
            AuthFlowView(container: container)
        }
        .fullScreenCover(item: $router.presentedVideo) { route in
            VideoDetailView(
                viewModel: container.makeVideoDetailViewModel(videoID: route.id),
                pool: container.playerPool,
                interactions: container.videoInteractions,
                container: container
            )
            // La feuille de connexion doit pouvoir s'ouvrir par-dessus la vidéo seule.
            .sheet(isPresented: $session.isPresentingSignIn) {
                AuthFlowView(container: container)
            }
        }
        // Profil ouvert par un lien d'app (ADR-056), avec sa propre pile.
        .sheet(item: $router.presentedProfile) { route in
            NavigationStack {
                ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
                    .appDestinations(container)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer", systemImage: "xmark") { router.presentedProfile = nil }
                        }
                    }
            }
            .environment(container.stories)
        }
        // Visionneuse de stories (ADR-051), sauf quand la vidéo seule est ouverte : elle la présente elle-même.
        .storiesPresenter(container) { container.router.presentedVideo == nil }
        // Live (ADR-053), par-dessus tout.
        .livePresenter(container)
        // « + » de « Ta story » : onglet Publier, en mode Story.
        .onChange(of: router.requestedPublishMode) { _, mode in
            if mode != nil { selection = .publish }
        }
        .environment(container.stories)
        .alert(
            "Session expirée",
            isPresented: Binding(
                get: { session.notice != nil },
                set: { if !$0 { session.notice = nil } }
            )
        ) {
            Button("Se connecter") { session.requestSignIn() }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text(session.notice ?? "")
        }
    }
}
