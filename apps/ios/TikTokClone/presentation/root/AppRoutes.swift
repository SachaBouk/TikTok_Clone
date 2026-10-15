import SwiftUI

// Écrans poussés dans les piles de navigation (feed, profil, vidéo seule). Chaque pile enregistre les mêmes
// destinations (`appDestinations`) : un profil s'ouvre de la même façon depuis une vidéo, une liste ou un profil.

struct ProfileRoute: Hashable {
    let username: String
}

struct FollowListRoute: Hashable {
    let kind: FollowListKind
    let username: String
}

// Écrans de son propre compte.
enum AccountRoute: Hashable {
    case settings
    case viewHistory
    case commentHistory
    case blockedAccounts
    case interests
    // Paywall et portefeuille de jetons (ADR-009).
    case wallet(PaywallSource)
}

// Recherche (ADR-049), ouverte par la loupe du feed.
struct SearchRoute: Hashable {}

// Page d'un hashtag (ADR-049) : nom sans « # ».
struct HashtagRoute: Hashable, Identifiable {
    var id: String { name }
    let name: String
}

// Chemin de la pile qui affiche l'écran, pour pousser une route par valeur depuis du code : hashtag touché dans une
// description, résultat de recherche (ADR-049). Un `NavigationLink(value:)` ne pousse rien dans un écran poussé par
// `navigationDestination(item:)`, et ne se déclenche plus si on lui ajoute un geste (`simultaneousGesture`).
extension EnvironmentValues {
    @Entry var navigationPath: Binding<NavigationPath>? = nil
}

extension View {
    func providesNavigationPath(_ path: Binding<NavigationPath>) -> some View {
        environment(\.navigationPath, path)
    }
}

// Lecteur vertical ouvert depuis une grille, sur la vidéo touchée.
struct VideoPlayerRoute: Hashable {
    let id = UUID()
    let list: VideoList
    let page: FeedPage
    let startIndex: Int

    static func == (lhs: VideoPlayerRoute, rhs: VideoPlayerRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension View {
    func appDestinations(_ container: AppContainer) -> some View {
        self
            .navigationDestination(for: ProfileRoute.self) { route in
                ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
            }
            .navigationDestination(for: FollowListRoute.self) { route in
                FollowListView(viewModel: container.makeFollowListViewModel(route))
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(viewModel: container.makeSearchViewModel())
            }
            .navigationDestination(for: HashtagRoute.self) { route in
                HashtagView(viewModel: container.makeHashtagViewModel(name: route.name))
            }
            .navigationDestination(for: VideoPlayerRoute.self) { route in
                VideoListPlayerView(route: route, container: container)
            }
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .settings: AccountSettingsView(viewModel: container.makeAccountSettingsViewModel(), wallet: container.wallet)
                case .viewHistory: ViewHistoryView(viewModel: container.makeViewHistoryViewModel(), container: container)
                case .commentHistory: CommentHistoryView(viewModel: container.makeCommentHistoryViewModel(), router: container.router)
                case .blockedAccounts: BlockedAccountsView(viewModel: container.makeBlockedAccountsViewModel())
                case .interests: InterestsSettingsView(viewModel: container.makeInterestsSettingsViewModel())
                case .wallet(let source): WalletView(source: source, container: container)
                }
            }
    }
}
