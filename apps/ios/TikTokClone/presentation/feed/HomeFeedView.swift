import SwiftUI

// Accueil : feed des abonnements (ADR-048) et feed principal (« Pour toi », ADR-016), choisis en haut de l'écran.
// - L'app s'ouvre toujours sur « Pour toi » (choix du développeur, comme TikTok).
// - Les deux feeds restent en place : chacun garde sa position quand on passe de l'un à l'autre.
// - Le feed des abonnements n'est chargé qu'à sa première ouverture, puis rechargé quand on y revient après un
//   abonnement ou un désabonnement fait dans l'app (`VideoInteractionsModel.followsVersion`), ou quand l'un d'eux
//   aboutit pendant qu'il est affiché. Il s'arrête à sa fin.
// - En invité, il invite à se connecter.
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
            feed(forYou, shown: selection == .forYou, emptyState: .feed)
            if !session.isSignedIn {
                if selection == .following { guestPrompt }
            } else if let following {
                feed(following, shown: selection == .following, emptyState: followingEmptyState)
            }
        }
        .background(.black)
        .overlay(alignment: .top) { FeedSelector(selection: $selection) }
        .onChange(of: selection) { showFollowingIfSelected() }
        // Abonnement confirmé par l'API alors que le feed des abonnements est déjà affiché (toucher « Abonnements »
        // pendant l'envoi, désabonnement depuis un profil ouvert par-dessus).
        .onChange(of: container.videoInteractions.followsVersion) { showFollowingIfSelected() }
        .onChange(of: session.isSignedIn) { _, isSignedIn in
            // Un autre compte se connectera peut-être : son feed des abonnements repartira de zéro.
            if !isSignedIn { following = nil }
            showFollowingIfSelected()
        }
    }

    private func feed(_ viewModel: FeedViewModel, shown: Bool, emptyState: FeedEmptyState) -> some View {
        FeedView(
            viewModel: viewModel,
            pool: container.playerPool,
            interactions: container.videoInteractions,
            container: container,
            isTabActive: isTabActive && shown,
            emptyState: emptyState
        )
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }

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
