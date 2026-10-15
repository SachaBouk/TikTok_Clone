import Foundation
import Observation

// Choix d'amis pour un chat de groupe (ADR-059) : à la création (« Créer un chat de groupe ») ou pour ajouter des
// membres. On ne propose que des amis (abonnés mutuels), comme l'exige l'API.
// - « Suggéré » : ses abonnements qui le suivent en retour, page par page (plusieurs pages lues si elles comptent peu
//   d'amis).
// - Recherche par nom ou pseudo : 300 ms après la frappe, recherche de comptes (ADR-049) restreinte aux amis.
// - Cases à cocher, dans l'ordre du choix ; au plus `maxSelection` comptes.
@MainActor
@Observable
final class FriendPickerModel {
    enum Mode: Equatable {
        case create
        // Ajout dans un groupe : ses membres ne sont pas proposés.
        case add(conversationID: String, members: Set<String>, remaining: Int)
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let mode: Mode
    private(set) var suggested: [UserSummary] = []
    // Résultats de la recherche ; nil sans texte.
    private(set) var results: [UserSummary]?
    private(set) var selected: [UserSummary] = []
    private(set) var state: State = .idle
    private(set) var isSearching = false
    private(set) var isSubmitting = false
    var errorMessage: String?
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    private var nextCursor: String?
    private var hasMore = true
    private var searchTask: Task<Void, Never>?
    private let loadFriends: LoadFriendsUseCase
    private let createGroup: CreateGroupUseCase
    private let session: SessionStore
    private let searchDelay: Duration
    // Pages d'abonnements lues d'affilée au plus pour trouver des amis.
    private static let pagesPerLoad = 5

    init(
        mode: Mode,
        loadFriends: LoadFriendsUseCase,
        createGroup: CreateGroupUseCase,
        session: SessionStore,
        searchDelay: Duration = .milliseconds(300)
    ) {
        self.mode = mode
        self.loadFriends = loadFriends
        self.createGroup = createGroup
        self.session = session
        self.searchDelay = searchDelay
    }

    // Comptes affichés : la recherche, sinon les suggestions ; jamais un membre du groupe.
    var displayed: [UserSummary] {
        let excluded: Set<String> = if case .add(_, let members, _) = mode { members } else { [] }
        return (results ?? suggested).filter { !excluded.contains($0.id) }
    }

    var maxSelection: Int {
        switch mode {
        case .create: GroupRules.maxMembers - 1
        case .add(_, _, let remaining): remaining
        }
    }

    var canSubmit: Bool {
        guard !isSubmitting else { return false }
        switch mode {
        case .create: return GroupRules.canCreate(selected: selected.count)
        case .add: return !selected.isEmpty && selected.count <= maxSelection
        }
    }

    // « Créer (3) », « Ajouter (2) ».
    var submitTitle: String {
        let action = mode == .create ? "Créer" : "Ajouter"
        return selected.isEmpty ? action : "\(action) (\(selected.count))"
    }

    // Ce qui manque encore pour créer : « Choisis au moins 2 amis ».
    var hint: String? {
        switch mode {
        case .create where selected.count < GroupRules.minFriends:
            return "Choisis au moins \(GroupRules.minFriends) amis."
        case _ where selected.count >= maxSelection:
            return "\(maxSelection) \(maxSelection > 1 ? "comptes" : "compte") au plus."
        default:
            return nil
        }
    }

    func isSelected(_ user: UserSummary) -> Bool { selected.contains { $0.id == user.id } }

    func toggle(_ user: UserSummary) {
        if isSelected(user) {
            selected.removeAll { $0.id == user.id }
        } else if selected.count < maxSelection {
            selected.append(user)
        }
    }

    func loadFirstIfNeeded() async {
        guard state == .idle else { return }
        await loadMore()
    }

    // Abonnements suivants, jusqu'à trouver des amis (ou la fin de la liste).
    func loadMore() async {
        guard hasMore, state != .loading, let username = session.profile?.username else { return }
        state = .loading
        do {
            var pages = 0
            var found = 0
            repeat {
                let page = try await loadFriends(username: username, cursor: nextCursor)
                let known = Set(suggested.map(\.id))
                let fresh = page.friends.filter { !known.contains($0.id) }
                suggested += fresh
                found += fresh.count
                nextCursor = page.nextCursor
                hasMore = page.nextCursor != nil
                pages += 1
            } while hasMore && found == 0 && pages < Self.pagesPerLoad
            state = .loaded
        } catch AppError.sessionExpired {
            session.sessionExpired()
            state = .loaded
        } catch {
            state = .failed(AppError.from(error).message)
        }
    }

    // Dernier compte affiché : la suite des suggestions (pas pendant une recherche).
    func loadMore(ifNeededAfter user: UserSummary) async {
        guard results == nil, user.id == suggested.last?.id else { return }
        await loadMore()
    }

    // Création : le groupe, ou nil (message d'erreur).
    func create() async -> Conversation? {
        guard mode == .create, canSubmit else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            return try await createGroup(userIDs: selected.map(\.id), name: "")
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AppError.from(error).message
        }
        return nil
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [searchDelay] in
            try? await Task.sleep(for: searchDelay)
            guard !Task.isCancelled else { return }
            let found = try? await loadFriends.search(text)
            guard !Task.isCancelled else { return }
            results = found ?? []
            isSearching = false
        }
    }
}
