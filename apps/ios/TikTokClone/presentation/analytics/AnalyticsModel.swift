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

    // Prévenu à chaque changement du consentement (Mux Data, ADR-074, suit le même accord).
    @ObservationIgnored var consentChanged: ((Bool) -> Void)?

    // Incrémenté quand un groupe est tiré, forcé ou oublié (écran « Expériences » du build Debug).
    private(set) var experimentsVersion = 0

    private let service: any AnalyticsService
    private let preferences: any PreferencesStore
    private let overrides: any ExperimentOverrides
    // Compte identifié auprès du service, pour ne l'identifier qu'une fois par connexion.
    private var identifiedUserID: String?

    init(service: any AnalyticsService, preferences: any PreferencesStore, overrides: any ExperimentOverrides = NoExperimentOverrides()) {
        self.service = service
        self.preferences = preferences
        self.overrides = overrides
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
        consentChanged?(granted)
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

    // Groupe de l'utilisateur dans une expérience (ADR-077), à demander au moment où l'expérience change ce qu'il voit :
    // c'est là que le groupe est tiré et l'exposition enregistrée (`$feature_flag_called` par le SDK, puis
    // `experiment_exposed` une fois). Dans l'ordre : variante forcée (Debug), groupe déjà tiré sur cet appareil (gardé
    // même si l'identifiant PostHog change à la connexion), témoin sans consentement (rien n'est lu), variante de
    // PostHog, sinon témoin pour cette fois (flags pas encore chargés ou variante inconnue).
    func decide(_ experiment: Experiment) -> ExperimentDecision {
        if let forced = overrides.forcedVariant(of: experiment.flag), experiment.isKnown(forced) {
            return ExperimentDecision(variant: forced, source: .forced)
        }
        if let stored = preferences.experimentAssignments[experiment.flag], experiment.isKnown(stored) {
            return ExperimentDecision(variant: stored, source: .stored)
        }
        guard isEnabled else { return ExperimentDecision(variant: experiment.control, source: .noConsent) }
        guard let variant = service.variant(of: experiment.flag), experiment.isKnown(variant) else {
            return ExperimentDecision(variant: experiment.control, source: .unavailable)
        }
        preferences.setExperimentAssignment(variant, of: experiment.flag)
        experimentsVersion += 1
        track(.experimentExposed(experiment, variant: variant))
        return ExperimentDecision(variant: variant, source: .assigned)
    }

    // Comme `decide`, en laissant aux flags le temps d'arriver (premier lancement : le SDK démarre au consentement et
    // charge ses flags par le réseau) : relu toutes les 250 ms pendant `timeout` au plus.
    func decideWhenLoaded(_ experiment: Experiment, timeout: Duration = .seconds(2)) async -> ExperimentDecision {
        var decision = decide(experiment)
        let deadline = ContinuousClock.now + timeout
        while decision.source == .unavailable, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { break }
            decision = decide(experiment)
        }
        return decision
    }

    // Écran « Expériences » (Debug) : groupe tiré, variante forcée, oubli des groupes tirés.
    func storedVariant(of experiment: Experiment) -> String? {
        _ = experimentsVersion
        return preferences.experimentAssignments[experiment.flag]
    }

    func forcedVariant(of experiment: Experiment) -> String? {
        _ = experimentsVersion
        return overrides.forcedVariant(of: experiment.flag)
    }

    func setForcedVariant(_ variant: String?, of experiment: Experiment) {
        overrides.setForcedVariant(variant, of: experiment.flag)
        experimentsVersion += 1
    }

    func clearExperimentAssignments() {
        preferences.clearExperimentAssignments()
        experimentsVersion += 1
    }

    // Expérience « invitation invité » (ADR-024) : tranchée une fois par installation, quand le seuil de vidéos est
    // atteint ; vrai si l'invitation doit s'afficher. Variante forcée : à chaque seuil atteint.
    func shouldPromptGuest() -> Bool {
        // Tranchée avant le catalogue (ADR-077) : plus jamais.
        guard !preferences.guestPromptDecided else { return false }
        let decision = decide(Experiments.guestSignupPrompt)
        // Déjà tirée : l'invitation a eu sa chance. Pas de consentement ou flags pas chargés : rien (réessayé au
        // prochain seuil, nouvelle session du feed).
        guard decision.source == .forced || decision.source == .assigned, decision.variant == GuestPromptExperiment.promptVariant else {
            return false
        }
        track(.guestPromptShown)
        return true
    }
}
