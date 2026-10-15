import Foundation

// Réglages locaux dans UserDefaults : ni secret ni donnée de compte.
struct UserDefaultsPreferencesStore: PreferencesStore, @unchecked Sendable {
    // UserDefaults est sûr entre fils d'exécution (documenté par Apple), mais pas déclaré Sendable.
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let analyticsConsent = "analyticsConsent"
        static let guestPromptDecided = "guestPromptDecided"
        static let searchHistory = "searchHistory"
        static let dismissedSuggestions = "dismissedSuggestions"
        static let onboardingCompleted = "onboardingCompleted"
        static let feedSwipeHintShown = "feedSwipeHintShown"
    }

    var analyticsConsent: Bool? {
        defaults.object(forKey: Key.analyticsConsent) as? Bool
    }

    func setAnalyticsConsent(_ consent: Bool) {
        defaults.set(consent, forKey: Key.analyticsConsent)
    }

    var guestPromptDecided: Bool {
        defaults.bool(forKey: Key.guestPromptDecided)
    }

    func markGuestPromptDecided() {
        defaults.set(true, forKey: Key.guestPromptDecided)
    }

    var onboardingCompleted: Bool {
        defaults.bool(forKey: Key.onboardingCompleted)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Key.onboardingCompleted)
    }

    var feedSwipeHintShown: Bool {
        defaults.bool(forKey: Key.feedSwipeHintShown)
    }

    func markFeedSwipeHintShown() {
        defaults.set(true, forKey: Key.feedSwipeHintShown)
    }
}

// Historique des recherches (ADR-049) : sur l'appareil seulement.
// Entrées en JSON (ADR-057 : avec leur date) ; une liste de textes gardée avant est relue sans date.
extension UserDefaultsPreferencesStore: SearchHistoryStore {
    var searchHistory: [SearchHistoryEntry] {
        if let data = defaults.data(forKey: Key.searchHistory), let entries = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) {
            return entries
        }
        return (defaults.stringArray(forKey: Key.searchHistory) ?? []).map { SearchHistoryEntry(query: $0) }
    }

    func setSearchHistory(_ entries: [SearchHistoryEntry]) {
        if entries.isEmpty {
            defaults.removeObject(forKey: Key.searchHistory)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Key.searchHistory)
        }
    }
}

// Suggestions de comptes écartées (ADR-058) : sur l'appareil seulement.
extension UserDefaultsPreferencesStore: DismissedSuggestionsStore {
    var dismissedSuggestions: [String] {
        defaults.stringArray(forKey: Key.dismissedSuggestions) ?? []
    }

    func setDismissedSuggestions(_ ids: [String]) {
        if ids.isEmpty {
            defaults.removeObject(forKey: Key.dismissedSuggestions)
        } else {
            defaults.set(ids, forKey: Key.dismissedSuggestions)
        }
    }
}
