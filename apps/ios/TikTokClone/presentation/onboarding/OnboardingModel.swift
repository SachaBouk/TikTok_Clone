import Foundation
import Observation

// Onboarding du premier lancement (ADR-055) : introduction puis écran « Connexion », une seule fois par installation,
// seulement si personne n'est connecté. Une connexion, une inscription ou « Continuer sans compte » le terminent.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var isPresented = false
    // Indication « Balaie vers le haut pour en voir plus » sur la première vidéo du feed (ADR-055) : une fois par
    // installation, à tout le monde (inscription, connexion ou invité), et de nouveau après chaque inscription.
    private(set) var showsFeedSwipeHint: Bool
    // Expérience « feed-swipe-hint » (ADR-077) tranchée : l'indication peut s'afficher. Tant qu'elle ne l'est pas,
    // l'indication attend (le groupe est tiré au moment où elle s'afficherait).
    private(set) var isFeedSwipeHintAllowed = false

    private let preferences: any PreferencesStore

    init(preferences: any PreferencesStore) {
        self.preferences = preferences
        showsFeedSwipeHint = !preferences.feedSwipeHintShown
    }

    // Premier défilement ou premier toucher : l'indication ne revient plus.
    func feedSwipeHintSeen() {
        guard showsFeedSwipeHint else { return }
        showsFeedSwipeHint = false
        preferences.markFeedSwipeHintShown()
    }

    // Groupe de l'expérience, demandé par le feed quand l'indication s'afficherait. Variante « hidden » : elle est vue
    // comme déjà montrée, et ne revient pas après une inscription (le groupe est gardé).
    func decideFeedSwipeHint(_ variant: () async -> String) async {
        guard showsFeedSwipeHint, !isFeedSwipeHintAllowed else { return }
        let decided = await variant()
        guard showsFeedSwipeHint else { return }
        if decided == Experiments.feedSwipeHint.control {
            isFeedSwipeHintAllowed = true
        } else {
            feedSwipeHintSeen()
        }
    }

    // Inscription terminée (fin du tutoriel) : l'indication revient sur le feed, même déjà vue sur cet iPhone, jusqu'au
    // prochain défilement ou toucher.
    func showFeedSwipeHint() {
        showsFeedSwipeHint = true
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
