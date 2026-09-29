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
    // Paywall et portefeuille de jetons (ADR-009).
    case wallet(PaywallSource)
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
            .navigationDestination(for: VideoPlayerRoute.self) { route in
                VideoListPlayerView(route: route, container: container)
            }
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .settings: AccountSettingsView(viewModel: container.makeAccountSettingsViewModel(), wallet: container.wallet)
                case .viewHistory: ViewHistoryView(viewModel: container.makeViewHistoryViewModel(), container: container)
                case .commentHistory: CommentHistoryView(viewModel: container.makeCommentHistoryViewModel(), router: container.router)
                case .blockedAccounts: BlockedAccountsView(viewModel: container.makeBlockedAccountsViewModel())
                case .wallet(let source): WalletView(source: source, container: container)
                }
            }
    }
}

