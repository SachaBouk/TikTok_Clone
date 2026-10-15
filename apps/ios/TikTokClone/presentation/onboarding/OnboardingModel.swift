import Foundation
import Observation

// Onboarding du premier lancement (ADR-055) : introduction puis écran « Connexion », une seule fois par installation,
// seulement si personne n'est connecté. Une connexion, une inscription ou « Continuer sans compte » le terminent.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var isPresented = false

    private let preferences: any PreferencesStore

    init(preferences: any PreferencesStore) {
        self.preferences = preferences
    }

    // Session reprise au lancement. Déjà connecté (compte d'une version précédente) : rien à montrer, jamais.
    func sessionRestored(signedIn: Bool) {
        guard !preferences.onboardingCompleted else { return }
        if signedIn {
            preferences.markOnboardingCompleted()
        } else {
            isPresented = true
        }
    }

    func finish() {
        preferences.markOnboardingCompleted()
        isPresented = false
    }
}
