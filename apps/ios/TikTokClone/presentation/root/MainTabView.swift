import SwiftUI

// Barre d'onglets native. En invité, seul l'accueil est accessible ; les autres onglets proposent de se connecter.
struct MainTabView: View {
    enum Destination: Hashable {
        case home, publish, inbox, profile
    }

    let container: AppContainer
    @Environment(SessionStore.self) private var session
    @State private var selection: Destination = .home
    // Écrans poussés au-dessus du feed (profils, lecteur d'une grille) : le feed se met en pause.
    @State private var feedPath = NavigationPath()
    // Chemins des autres onglets : une page de hashtag y est poussée par valeur (ADR-049).
    @State private var inboxPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    private var router: AppRouter { container.router }

    var body: some View {
        @Bindable var session = session
        @Bindable var router = container.router
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house", value: .home) {
                NavigationStack(path: $feedPath) {
                    // « Abonnements | Pour toi » (ADR-048).
                    HomeFeedView(
                        container: container,
                        // En pause pendant qu'une vidéo seule est ouverte par-dessus.
                        isTabActive: selection == .home && router.presentedVideo == nil
                    )
                    .toolbar(.hidden, for: .navigationBar)
                    .appDestinations(container)
                }
                .providesNavigationPath($feedPath)
                .environment(\.isTabActive, selection == .home && router.presentedVideo == nil)
            }
            Tab("Publier", systemImage: "plus.app", value: .publish) {
                SignedInOnly(title: "Publier", systemImage: "plus.app", reason: "Connecte-toi pour publier une vidéo.") {
                    PublishView(draft: container.makePublishDraftViewModel(), publishing: container.publishing, router: container.router)
                }
            }
            // Publications en cours d'envoi ou de traitement.
            .badge(container.publishing.inProgressCount)
            Tab("Boîte de réception", systemImage: "tray", value: .inbox) {
                SignedInOnly(title: "Boîte de réception", systemImage: "tray", reason: "Connecte-toi pour voir ton activité et tes messages.") {
                    NavigationStack(path: $inboxPath) {
                        InboxView(container: container)
                            .appDestinations(container)
                    }
                    .providesNavigationPath($inboxPath)
                    .environment(\.isTabActive, selection == .inbox && router.presentedVideo == nil)
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
                    .environment(\.isTabActive, selection == .profile && router.presentedVideo == nil)
                }
            }
        }
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
