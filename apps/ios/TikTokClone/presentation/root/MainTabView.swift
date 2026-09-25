import SwiftUI

// Barre d'onglets native. En invité, seul l'accueil est accessible ; les autres onglets proposent de se connecter.
struct MainTabView: View {
    enum Destination: Hashable {
        case home, publish, inbox, profile
    }

    let container: AppContainer
    @Environment(SessionStore.self) private var session
    @State private var selection: Destination = .home

    var body: some View {
        @Bindable var session = session
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house", value: .home) {
                FeedView(viewModel: container.makeFeedViewModel(), pool: container.playerPool, isTabActive: selection == .home)
            }
            Tab("Publier", systemImage: "plus.app", value: .publish) {
                SignedInOnly(title: "Publier", systemImage: "plus.app", reason: "Connecte-toi pour publier une vidéo.") {
                    ComingSoonView(title: "Publier", systemImage: "plus.app")
                }
            }
            Tab("Boîte de réception", systemImage: "tray", value: .inbox) {
                SignedInOnly(title: "Boîte de réception", systemImage: "tray", reason: "Connecte-toi pour voir ton activité et tes messages.") {
                    ComingSoonView(title: "Boîte de réception", systemImage: "tray")
                }
            }
            Tab("Profil", systemImage: "person", value: .profile) {
                SignedInOnly(title: "Profil", systemImage: "person.crop.circle", reason: "Connecte-toi pour créer ton profil et suivre des comptes.") {
                    ProfileView(viewModel: container.makeProfileViewModel())
                }
            }
        }
        .sheet(isPresented: $session.isPresentingSignIn) {
            AuthFlowView(container: container)
        }
        .alert("Session expirée", isPresented: Binding(
            get: { session.notice != nil },
            set: { if !$0 { session.notice = nil } }
        )) {
            Button("Se connecter") { session.requestSignIn() }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text(session.notice ?? "")
        }
    }
}

struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("Bientôt disponible."))
                .navigationTitle(title)
        }
    }
}
