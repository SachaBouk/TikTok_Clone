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
extension UserDefaultsPreferencesStore: SearchHistoryStore {
    var searchHistory: [String] {
        defaults.stringArray(forKey: Key.searchHistory) ?? []
    }

    func setSearchHistory(_ queries: [String]) {
        if queries.isEmpty {
            defaults.removeObject(forKey: Key.searchHistory)
        } else {
            defaults.set(queries, forKey: Key.searchHistory)
        }
    }
}
