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
}
