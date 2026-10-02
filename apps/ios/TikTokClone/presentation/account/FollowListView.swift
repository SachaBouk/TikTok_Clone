import Observation
import SwiftUI

// Abonnés ou abonnements d'un compte (listes publiques), du follow le plus récent au plus ancien.
// Chaque ligne a son bouton d'abonnement (état partagé avec les profils et le feed).
@MainActor
@Observable
final class FollowListViewModel {
    let kind: FollowListKind
    let username: String
    let list: PagedList<FollowEntry>
    var errorMessage: String?

    private let interactions: VideoInteractionsModel
    private let session: SessionStore

    init(kind: FollowListKind, username: String, loadFollows: LoadFollowsUseCase, interactions: VideoInteractionsModel, session: SessionStore) {
        self.kind = kind
        self.username = username
        self.interactions = interactions
        self.session = session
        list = PagedList(session: session) { cursor in
            let page = try await loadFollows(kind, username: username, cursor: cursor)
            return (page.entries, page.nextCursor)
        }
    }

    // Comptes bloqués depuis le chargement (profil ouvert depuis la liste) : leurs lignes disparaissent.
    var blockedUserIDs: Set<String> { interactions.blockedUserIDs }

    func removeBlocked(_ ids: Set<String>) {
        list.remove { ids.contains($0.user.id) }
    }

    // Nil pour son propre compte (pas de bouton).
    func status(of entry: FollowEntry) -> FollowStatus? {
        guard session.profile?.id != entry.user.id else { return nil }
        let following = interactions.isFollowing(entry.user.id, loaded: entry.viewer?.following ?? false)
        return FollowStatus(following: following, followedBy: entry.viewer?.followedBy ?? false)
    }

    func toggleFollow(_ entry: FollowEntry) async {
        guard let status = status(of: entry) else { return }
        if case .failed(let message) = await interactions.setFollowing(entry.user, active: !status.isFollowing, wasFollowing: status.isFollowing) {
            errorMessage = message
        }
    }
}

struct FollowListView: View {
    @State private var viewModel: FollowListViewModel

    init(viewModel: FollowListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            ForEach(viewModel.list.items) { entry in
                HStack(spacing: 12) {
                    NavigationLink(value: ProfileRoute(username: entry.user.username)) {
                        UserRow(user: entry.user)
                    }
                    if let status = viewModel.status(of: entry) {
                        FollowButton(status: status) { Task { await viewModel.toggleFollow(entry) } }
                    }
                }
                .onAppear { Task { await viewModel.list.loadMore(ifNeededAfter: entry) } }
            }
        }
        .listStyle(.plain)
        .overlay {
            PagedListPlaceholder(state: viewModel.list.state, isEmpty: viewModel.list.items.isEmpty, emptyTitle: emptyTitle) {
                await viewModel.list.loadFirst()
            }
        }
        .navigationTitle(viewModel.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.list.loadFirstIfNeeded() }
        .refreshable { await viewModel.list.loadFirst() }
        .onChange(of: viewModel.blockedUserIDs) { _, ids in viewModel.removeBlocked(ids) }
        .alert(
            "Abonnements",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var emptyTitle: String {
        viewModel.kind == .followers ? "Aucun abonné" : "Aucun abonnement"
    }
}

// Photo, nom et pseudo d'un compte.
struct UserRow: View {
    let user: UserSummary

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarURL, name: user.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FollowButton: View {
    let status: FollowStatus
    let action: () -> Void

    var body: some View {
        Group {
            if status.isFollowing {
                Button(status.title, action: action).buttonStyle(.bordered)
            } else {
                Button(status.title, action: action).buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}

// Chargement, erreur ou liste vide, par-dessus une liste paginée.
struct PagedListPlaceholder: View {
    let state: PagedListState
    let isEmpty: Bool
    let emptyTitle: String
    var emptySystemImage = "person.2"
    let retry: () async -> Void

    var body: some View {
        if isEmpty {
            switch state {
            case .idle, .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Chargement impossible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Réessayer") { Task { await retry() } }
                }
            case .loaded:
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
            }
        }
    }
}
