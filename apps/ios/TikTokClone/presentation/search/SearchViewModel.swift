import Foundation
import Observation

// Écran de recherche (ADR-049). Avant la saisie : historique et hashtags tendance. Pendant la saisie, après
// `debounce` sans frappe : hashtags qui commencent par le texte, puis comptes (paginés, bouton « Suivre »).
// Un texte qui commence par « # » ne cherche que des hashtags.
@MainActor
@Observable
final class SearchViewModel {
    static let hashtagSuggestions = 5
    static let maxQueryLength = 50

    var text = "" {
        didSet { if text != oldValue { textChanged() } }
    }
    // Texte de la dernière recherche lancée (résultats affichés).
    private(set) var query = ""
    private(set) var hashtags: [Hashtag] = []
    // Recherche dont les hashtags sont arrivés (écran « Aucun hashtag »).
    private(set) var completedQuery: String?
    private(set) var accounts: PagedList<AccountSearchResult>?
    private(set) var trending: [Hashtag] = []
    var errorMessage: String?

    let history: SearchHistoryModel
    private let searchAccounts: SearchAccountsUseCase
    private let searchHashtags: SearchHashtagsUseCase
    private let loadTrending: LoadTrendingHashtagsUseCase
    private let interactions: VideoInteractionsModel
    private let session: SessionStore
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(
        searchAccounts: SearchAccountsUseCase,
        searchHashtags: SearchHashtagsUseCase,
        loadTrending: LoadTrendingHashtagsUseCase,
        history: SearchHistoryModel,
        interactions: VideoInteractionsModel,
        session: SessionStore,
        debounce: Duration = .milliseconds(300)
    ) {
        self.searchAccounts = searchAccounts
        self.searchHashtags = searchHashtags
        self.loadTrending = loadTrending
        self.history = history
        self.interactions = interactions
        self.session = session
        self.debounce = debounce
    }

    var isSearching: Bool { !trimmedText.isEmpty }

    // Comptes bloqués depuis le chargement (profil ouvert depuis les résultats) : leurs lignes disparaissent.
    var blockedUserIDs: Set<String> { interactions.blockedUserIDs }

    func loadTrendingIfNeeded() async {
        guard trending.isEmpty else { return }
        trending = (try? await loadTrending()) ?? []
    }

    // Validation du champ : recherche tout de suite, et retenue dans l'historique.
    func submit() {
        guard isSearching else { return }
        history.record(trimmedText)
        searchTask?.cancel()
        searchTask = Task { await search(trimmedText) }
    }

    // Recherche de l'historique touchée : remise dans le champ et lancée.
    func search(fromHistory query: String) {
        text = query
        submit()
    }

    // Un résultat ouvert (compte ou hashtag) : la recherche est retenue.
    func resultOpened() {
        if isSearching { history.record(trimmedText) }
    }

    func removeBlocked(_ ids: Set<String>) {
        accounts?.remove { ids.contains($0.user.id) }
    }

    // Nil pour son propre compte (pas de bouton).
    func status(of result: AccountSearchResult) -> FollowStatus? {
        guard session.profile?.id != result.user.id else { return nil }
        let following = interactions.isFollowing(result.user.id, loaded: result.viewer?.following ?? false)
        return FollowStatus(following: following, followedBy: result.viewer?.followedBy ?? false)
    }

    func toggleFollow(_ result: AccountSearchResult) async {
        guard let status = status(of: result) else { return }
        if case .failed(let message) = await interactions.setFollowing(result.user, active: !status.isFollowing, wasFollowing: status.isFollowing) {
            errorMessage = message
        }
    }

    // Attendu par les tests : la recherche en cours (après le délai de frappe).
    func waitForSearch() async {
        await searchTask?.value
    }

    // 50 caractères au plus (limite de l'API).
    private var trimmedText: String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxQueryLength)) }

    private func textChanged() {
        searchTask?.cancel()
        let current = trimmedText
        guard !current.isEmpty else {
            query = ""
            hashtags = []
            completedQuery = nil
            accounts = nil
            return
        }
        searchTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await search(current)
        }
    }

    private func search(_ text: String) async {
        query = text
        // Hashtags d'abord (réponse courte), sauf pour un pseudo (« @… ») ; comptes ensuite, sauf pour un hashtag.
        let found = text.hasPrefix("@") ? [] : ((try? await searchHashtags(prefix: text, limit: Self.hashtagSuggestions)) ?? [])
        guard !Task.isCancelled, query == text else { return }
        hashtags = found
        completedQuery = text
        guard !text.hasPrefix("#") else {
            accounts = nil
            return
        }
        let accounts = PagedList<AccountSearchResult>(session: session) { [searchAccounts] cursor in
            let page = try await searchAccounts(query: text, cursor: cursor)
            return (page.results, page.nextCursor)
        }
        self.accounts = accounts
        await accounts.loadFirst()
    }
}
