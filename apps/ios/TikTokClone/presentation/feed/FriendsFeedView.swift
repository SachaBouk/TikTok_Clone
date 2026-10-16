import SwiftUI

// Onglet « Amis » (ADR-054) : vidéos publiées des amis (comptes suivis qui suivent en retour), de la plus récente à la
// plus ancienne, dans le même lecteur que les autres feeds. Il s'arrête à sa fin.
// - Chargé à la première ouverture de l'onglet (la vue n'existe que pour un compte connecté).
// - Rechargé quand on revient sur l'onglet après un abonnement, un désabonnement ou un blocage fait dans l'app
//   (`VideoInteractionsModel.followsVersion`), ou quand l'un d'eux aboutit pendant qu'il est affiché.
// - Toucher l'onglet alors qu'il est affiché le recharge (comme l'accueil) : les deux points rose et cyan apparaissent en
//   haut à droite le temps du rechargement (0,8 s au moins), la flèche tourne dans la barre d'onglets.
struct FriendsFeedView: View {
    let container: AppContainer
    // Onglet « Amis » sélectionné, sans plein écran par-dessus.
    let isTabActive: Bool
    // « Découvrir « Pour toi » » de l'état vide : l'onglet Accueil.
    let discover: () -> Void
    @State private var viewModel: FeedViewModel
    // `followsVersion` au dernier chargement.
    @State private var loadedVersion: Int

    init(container: AppContainer, isTabActive: Bool, discover: @escaping () -> Void) {
        self.container = container
        self.isTabActive = isTabActive
        self.discover = discover
        _viewModel = State(initialValue: container.makeFriendsFeedViewModel())
        _loadedVersion = State(initialValue: container.videoInteractions.followsVersion)
    }

    var body: some View {
        FeedView(
            viewModel: viewModel,
            pool: container.playerPool,
            interactions: container.videoInteractions,
            container: container,
            isTabActive: isTabActive,
            emptyState: emptyState
        )
        .overlay(alignment: .top) {
            Text("Amis")
                .font(.headline)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        }
        .overlay(alignment: .topTrailing) {
            if container.router.isFriendsRefreshing {
                DotsLoader(size: 10)
                    .frame(width: 44, height: 36)
                    .padding(.trailing, 8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("friends.refreshing")
            }
        }
        .onChange(of: container.router.friendsRefreshRequests) { Task { await refreshFromTab() } }
        .onChange(of: isTabActive) { reloadIfFollowsChanged() }
        .onChange(of: container.videoInteractions.followsVersion) { reloadIfFollowsChanged() }
    }

    private func refreshFromTab() async {
        let router = container.router
        guard !router.isFriendsRefreshing else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { router.isFriendsRefreshing = true }
        async let minimum: Void = { try? await Task.sleep(for: HomeFeedView.refreshMinimumDuration) }()
        loadedVersion = container.videoInteractions.followsVersion
        await viewModel.reload()
        await minimum
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { router.isFriendsRefreshing = false }
    }

    private func reloadIfFollowsChanged() {
        let version = container.videoInteractions.followsVersion
        guard isTabActive, version != loadedVersion else { return }
        loadedVersion = version
        Task { await viewModel.reload() }
    }

    private var emptyState: FeedEmptyState {
        FeedEmptyState(
            title: "Aucune vidéo de tes amis",
            systemImage: "person.2",
            description: "Tes amis sont les comptes que tu suis et qui te suivent en retour. Leurs vidéos apparaîtront ici.",
            action: .init(title: "Découvrir « Pour toi »", run: discover)
        )
    }
}
