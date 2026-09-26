import Foundation
import Observation

// Mesure d'audience et tests A/B (ADR-013), partagés par toute l'app (AppContainer) : seul point d'entrée des
// écrans vers le port `AnalyticsService`.
// - Consentement (choix du développeur : opt-in, RGPD) : demandé au premier lancement, modifiable dans les réglages.
//   Rien n'est envoyé avant l'accord ; un refus ou un retrait coupe tout.
// - Compte connecté : identifié par son seul identifiant ; déconnexion : nouvel identifiant anonyme.
@MainActor
@Observable
final class AnalyticsModel {
    // Consentement donné (nil : pas encore demandé).
    private(set) var consent: Bool?
    // Feuille de consentement à montrer.
    var isAskingConsent = false

    private let service: any AnalyticsService
    private let preferences: any PreferencesStore
    // Compte identifié auprès du service, pour ne l'identifier qu'une fois par connexion.
    private var identifiedUserID: String?

    init(service: any AnalyticsService, preferences: any PreferencesStore) {
        self.service = service
        self.preferences = preferences
        consent = preferences.analyticsConsent
        if consent == true { service.start() }
    }

    var isEnabled: Bool { consent == true }

    // Au lancement : la question est posée une fois, tant qu'elle n'a pas de réponse.
    func askConsentIfNeeded() {
        if consent == nil { isAskingConsent = true }
    }

    func setConsent(_ granted: Bool) {
        isAskingConsent = false
        guard consent != granted else { return }
        consent = granted
        preferences.setAnalyticsConsent(granted)
        if granted {
            service.start()
            if let identifiedUserID { service.identify(userID: identifiedUserID) }
        } else {
            service.stop()
        }
    }

    // Connexion, déconnexion, compte supprimé (RootView).
    func sessionChanged(userID: String?) {
        guard userID != identifiedUserID else { return }
        let wasIdentified = identifiedUserID != nil
        identifiedUserID = userID
        guard isEnabled else { return }
        if let userID {
            service.identify(userID: userID)
        } else if wasIdentified {
            service.reset()
        }
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        service.track(event)
    }

    // Variante d'une expérience ; nil sans consentement (groupe témoin) : la lecture enregistre l'exposition.
    func variant(of flag: String) -> String? {
        guard isEnabled else { return nil }
        return service.variant(of: flag)
    }

    // Expérience « invitation invité » : tranchée une fois par installation ; vrai si l'invitation doit s'afficher.
    func shouldPromptGuest() -> Bool {
        guard !preferences.guestPromptDecided, isEnabled else { return false }
        let variant = variant(of: GuestPromptExperiment.flag)
        // Flags pas encore chargés : on réessaiera au prochain seuil (nouvelle session du feed).
        guard let variant else { return false }
        preferences.markGuestPromptDecided()
        guard variant == GuestPromptExperiment.promptVariant else { return false }
        track(.guestPromptShown)
        return true
    }
}
