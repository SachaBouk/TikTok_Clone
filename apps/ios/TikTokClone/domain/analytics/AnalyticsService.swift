// Port de la mesure d'audience et des tests A/B (ADR-013 : PostHog). L'implémentation n'envoie rien tant que
// `start` n'a pas été appelé (consentement donné) ; `stop` coupe tout (consentement retiré).
@MainActor
protocol AnalyticsService: AnyObject {
    func start()
    func stop()
    func track(_ event: AnalyticsEvent)
    // Compte connecté : identifiant du compte seul, sans propriété personnelle (choix du développeur). Les événements
    // envoyés en invité sur l'appareil lui sont rattachés.
    func identify(userID: String)
    // Déconnexion : nouvel identifiant anonyme.
    func reset()
    // Valeur d'un feature flag (variante d'une expérience), nil s'il est inconnu ou pas encore chargé. La lecture
    // enregistre l'exposition à l'expérience.
    func variant(of flag: String) -> String?
}

// Réglages locaux de l'appareil (hors compte).
protocol PreferencesStore: Sendable {
    // Consentement à la mesure d'audience : nil tant que la question n'a pas été posée.
    var analyticsConsent: Bool? { get }
    func setAnalyticsConsent(_ consent: Bool)
    // Expérience « invitation invité » déjà tranchée sur cet appareil (une fois par installation).
    var guestPromptDecided: Bool { get }
    func markGuestPromptDecided()
    // Onboarding (introduction et écran « Connexion ») déjà passé sur cet appareil (ADR-055).
    var onboardingCompleted: Bool { get }
    func markOnboardingCompleted()
    // Indication « Balaie vers le haut » déjà montrée sur le feed (ADR-055, une fois par installation).
    var feedSwipeHintShown: Bool { get }
    func markFeedSwipeHintShown()
}
