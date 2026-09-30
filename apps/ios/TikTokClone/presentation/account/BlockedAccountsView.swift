import Observation
import SwiftUI

// Comptes bloqués par le compte connecté (liste complète, du plus récent au plus ancien) ; débloquer.
@MainActor
@Observable
final class BlockedAccountsViewModel {
    private(set) var users: [UserSummary] = []
    private(set) var state: PagedListState = .idle
    var errorMessage: String?

    private let loadBlockedUsers: LoadBlockedUsersUseCase
    private let setBlocked: SetBlockedUseCase
    private let interactions: VideoInteractionsModel
    private let session: SessionStore

    init(loadBlockedUsers: LoadBlockedUsersUseCase, setBlocked: SetBlockedUseCase, interactions: VideoInteractionsModel, session: SessionStore) {
        self.loadBlockedUsers = loadBlockedUsers
        self.setBlocked = setBlocked
        self.interactions = interactions
        self.session = session
    }

    func load() async {
        if users.isEmpty { state = .loading }
        do {
            users = try await loadBlockedUsers()
            state = .loaded
        } catch {
            if let message = handle(error) { state = users.isEmpty ? .failed(message) : .loaded }
        }
    }

    // Débloquer ne rétablit pas les follows supprimés au blocage.
    func unblock(_ user: UserSummary) async {
        do {
            try await setBlocked(false, username: user.username)
            users.removeAll { $0.id == user.id }
            interactions.unblocked(user.id)
        } catch {
            errorMessage = handle(error)
        }
    }

    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        return error.message
    }
}

struct BlockedAccountsView: View {
    @State private var viewModel: BlockedAccountsViewModel

    init(viewModel: BlockedAccountsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List(viewModel.users, id: \.id) { user in
            HStack(spacing: 12) {
                NavigationLink(value: ProfileRoute(username: user.username)) {
                    UserRow(user: user)
                }
                Button("Débloquer") { Task { await viewModel.unblock(user) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .listStyle(.plain)
        .overlay {
            PagedListPlaceholder(state: viewModel.state, isEmpty: viewModel.users.isEmpty, emptyTitle: "Aucun compte bloqué",
                                 emptySystemImage: "hand.raised") { await viewModel.load() }
        }
        .navigationTitle("Comptes bloqués")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Comptes bloqués", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
