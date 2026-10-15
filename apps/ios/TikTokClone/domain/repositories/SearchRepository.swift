// Port de la recherche (ADR-049). Toutes les routes sont publiques (invité compris).
protocol SearchRepository: Sendable {
    // Comptes dont le pseudo ou le nom contient `query` ; 100 résultats au plus.
    func searchAccounts(query: String, cursor: String?) async throws -> AccountSearchPage
    // Hashtags qui commencent par `prefix`, du plus utilisé au moins utilisé.
    func searchHashtags(prefix: String, limit: Int) async throws -> [Hashtag]
    func trendingHashtags() async throws -> [Hashtag]
    // Un nom valide inconnu a 0 vidéo.
    func hashtag(name: String) async throws -> Hashtag
}

// Historique des recherches, sur l'appareil seulement (ADR-049).
protocol SearchHistoryStore: Sendable {
    var searchHistory: [SearchHistoryEntry] { get }
    func setSearchHistory(_ entries: [SearchHistoryEntry])
}
