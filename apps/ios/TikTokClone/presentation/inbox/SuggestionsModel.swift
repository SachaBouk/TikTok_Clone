import Foundation
import Observation

// Comptes suggérés (ADR-058), un seul modèle pour toute l'app (`AppContainer.suggestions`) : sous l'activité et sous les
// nouveaux followers. Chargés à la première ouverture, relus en tirant pour actualiser. Le × écarte une suggestion sur
// l'appareil ; les suggestions écartées sont oubliées à chaque changement de session.
@MainActor
@Observable
final class SuggestionsModel {
    enum State: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var all: [AccountSuggestion] = []
    private(set) var state: State = .idle
    private(set) var dismissed: DismissedSuggestions

    private let load: LoadSuggestionsUseCase
    private let store: any DismissedSuggestionsStore
    private let session: SessionStore

    init(load: LoadSuggestionsUseCase, store: any DismissedSuggestionsStore, session: SessionStore) {
        self.load = load
        self.store = store
        self.session = session
        dismissed = DismissedSuggestions(store.dismissedSuggestions)
    }

    // Suggestions affichées : sans celles écartées ni les comptes bloqués depuis le chargement.
    func visible(blocked: Set<String>) -> [AccountSuggestion] {
        all.filter { !dismissed.contains($0.id) && !blocked.contains($0.id) }
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await reload()
    }

    func reload() async {
        guard session.isSignedIn else { return }
        if all.isEmpty { state = .loading }
        do {
            all = try await load()
            state = .loaded
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            // Section discrète : en cas d'échec, elle n'apparaît simplement pas.
            state = all.isEmpty ? .failed : .loaded
        }
    }

    func dismiss(_ suggestion: AccountSuggestion) {
        dismissed.dismiss(suggestion.id)
        store.setDismissedSuggestions(dismissed.ids)
    }

    // Changement de session : rien ne reste d'un compte à l'autre.
    func reset() {
        all = []
        state = .idle
        dismissed = DismissedSuggestions()
        store.setDismissedSuggestions([])
    }
}
