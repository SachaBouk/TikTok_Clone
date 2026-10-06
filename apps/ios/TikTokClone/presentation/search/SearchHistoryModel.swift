import Foundation
import Observation

// Historique des recherches (ADR-049), un seul pour toute l'app (`AppContainer.searchHistory`) : gardé sur
// l'appareil, effacé à chaque changement de session (connexion, déconnexion, suppression du compte) pour n'être
// jamais visible d'un autre compte.
@MainActor
@Observable
final class SearchHistoryModel {
    private(set) var history: SearchHistory
    private let store: any SearchHistoryStore

    init(store: any SearchHistoryStore) {
        self.store = store
        history = SearchHistory(store.searchHistory)
    }

    var queries: [String] { history.queries }

    func record(_ query: String) {
        history.record(query)
        store.setSearchHistory(history.queries)
    }

    func remove(_ query: String) {
        history.remove(query)
        store.setSearchHistory(history.queries)
    }

    func clear() {
        history = SearchHistory()
        store.setSearchHistory([])
    }
}
