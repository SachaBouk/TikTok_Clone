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
    // Icônes des onglets Accueil et Amis pendant un rechargement (flèche qui tourne, `TabRefreshIcon`).
    @State private var homeIcon = TabRefreshIcon.standard
    @State private var friendsIcon = TabRefreshIcon.standard
    @State private var iconTasks: [Destination: Task<Void, Never>] = [:]
    private var router: AppRouter { container.router }

    // Toucher l'onglet déjà sélectionné : Accueil et Amis reviennent au feed s'il y a des écrans par-dessus, sinon le
    // rechargent (comme TikTok).
    private var tabSelection: Binding<Destination> {
        Binding(
            get: { selection },
            set: { new in
                if new == .home, selection == .home {
                    if feedPath.isEmpty { container.router.homeRefreshRequests += 1 } else { feedPath = NavigationPath() }
                }
                if new == .friends, selection == .friends, session.isSignedIn {
                    if friendsPath.isEmpty { container.router.friendsRefreshRequests += 1 } else { friendsPath = NavigationPath() }
                }
                // « + » (ADR-062) : la création s'ouvre en plein écran, l'onglet affiché ne change pas.
                if new == .publish {
                    if session.isSignedIn { container.router.openCreation() } else { session.requestSignIn() }
                    return
                }
                selection = new
            }
        )
    }

    // Étapes de l'icône d'un onglet, ~30 par seconde, jusqu'au retour de son icône après le rechargement.
    private func animateIcon(of tab: Destination) async {
        let start = Date.now
        var end: Date?
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(start)
            let refreshing = tab == .home ? container.router.isHomeRefreshing : container.router.isFriendsRefreshing
            if end == nil, !refreshing, TabRefreshIcon.canEnd(elapsed: elapsed) { end = .now }
            let icon = TabRefreshIcon.at(
                elapsed: elapsed, endedFor: end.map { Date.now.timeIntervalSince($0) }, symbol: tab == .home ? "house.fill" : "person.2.fill")
            if tab == .home { homeIcon = icon } else { friendsIcon = icon }
            if icon == .standard { return }
            try? await Task.sleep(for: TabRefreshIcon.frameInterval)
        }
    }

    private func startIconAnimation(_ tab: Destination) {
        iconTasks[tab]?.cancel()
        iconTasks[tab] = Task { await animateIcon(of: tab) }
    }

    // Icône d'un onglet de feed : la sienne, ou l'étape dessinée du rechargement.
    @ViewBuilder
    private func tabIcon(_ icon: TabRefreshIcon, systemImage: String) -> some View {
        switch icon {
        case .standard: Image(systemName: systemImage)
        case .frame(let symbol, let angle, let scale): Image(uiImage: TabRefreshIcon.image(symbol: symbol, angle: angle, scale: scale))
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
                    tabIcon(homeIcon, systemImage: "house")
                }
            }
            // Feed des amis (ADR-054), entre l'accueil et la publication.
            Tab(value: .friends) {
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
            } label: {
                Label {
                    Text("Amis")
                } icon: {
                    tabIcon(friendsIcon, systemImage: "person.2")
                }
            }
            // Jamais affiché : le toucher ouvre la création (`tabSelection`).
            Tab("Publier", systemImage: "plus.app", value: .publish) {
                Color.clear
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
            if refreshing { startIconAnimation(.home) }
        }
        .onChange(of: router.isFriendsRefreshing) { _, refreshing in
            if refreshing { startIconAnimation(.friends) }
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
        // Création (ADR-062), par-dessus les onglets ; une vidéo publiée ouvre le profil (publication en cours).
        .fullScreenCover(item: $router.presentedCreation) { route in
            CreationScreen(container: container, mode: route.mode, restoring: route.draft) { story in
                router.presentedCreation = nil
                if !story { router.publishedFromCreation += 1 }
            } onClose: {
                router.presentedCreation = nil
            }
        }
        .onChange(of: router.publishedFromCreation) {
            profilePath = NavigationPath()
            selection = .profile
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
