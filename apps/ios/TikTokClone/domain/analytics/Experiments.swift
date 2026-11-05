import Foundation

// Expériences A/B (ADR-013, ADR-077) : catalogue en un seul endroit, comme les événements. Chaque expérience est un
// feature flag multivarié de PostHog, de même clé ; ses variantes et son témoin sont fixés ici. Une variante inconnue
// de PostHog (flag mal configuré, booléen) est ignorée : l'utilisateur reste dans le témoin, sans être exposé.
struct Experiment: Sendable, Hashable, Identifiable {
    // Clé du feature flag dans PostHog.
    let flag: String
    // Nom et explication, pour l'écran « Expériences » du build Debug.
    let title: String
    let summary: String
    // Variante du groupe témoin : celle de tout le monde sans consentement, ou tant que les flags ne sont pas chargés.
    let control: String
    // Toutes les variantes, témoin compris, dans l'ordre de l'écran Debug.
    let variants: [String]

    var id: String { flag }

    func isKnown(_ variant: String) -> Bool { variants.contains(variant) }
}

enum Experiments {
    // ADR-024 : invitation à créer un compte après 5 vidéos regardées en invité.
    static let guestSignupPrompt = Experiment(
        flag: "guest-signup-prompt", title: "Invitation invité",
        summary: "Après 5 vidéos regardées sans compte, la connexion s'ouvre avec une invitation.",
        control: "control", variants: ["control", "prompt"])

    // ADR-077 : indication « Balaie vers le haut pour en voir plus » sur le feed, montrée (témoin) ou non.
    // Mesure : vidéos regardées pendant la première session, rétention D1.
    static let feedSwipeHint = Experiment(
        flag: "feed-swipe-hint", title: "Indication « Balaie vers le haut »",
        summary: "Montrée sur la première vidéo du feed (témoin), ou jamais.",
        control: "shown", variants: ["shown", "hidden"])

    // ADR-077 : premier carrousel de comptes suggérés du feed après la 8e vidéo (témoin) ou après la 4e.
    // Mesure : abonnements depuis le carrousel, vidéos regardées.
    static let suggestionCarouselSlot = Experiment(
        flag: "suggestion-carousel-slot", title: "Carrousel de comptes suggérés",
        summary: "Premier carrousel du feed « Pour toi » après la 8e vidéo (témoin) ou la 4e, puis toutes les 30.",
        control: "after-8", variants: ["after-8", "after-4"])

    static let all = [guestSignupPrompt, feedSwipeHint, suggestionCarouselSlot]
}

// Groupe d'un utilisateur dans une expérience, et d'où il vient.
struct ExperimentDecision: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        // Forcée dans le build Debug (argument de lancement ou écran « Expériences ») : jamais exposée.
        case forced
        // Tirée plus tôt sur cet appareil : gardée (une fois par installation).
        case stored
        // Tirée maintenant : exposition enregistrée.
        case assigned
        // Pas de consentement : témoin, rien n'est lu.
        case noConsent
        // Flags pas encore chargés, ou variante inconnue : témoin pour cette fois, réessayé plus tard.
        case unavailable
    }

    let variant: String
    let source: Source

    // Groupe définitif : il ne changera plus sur cet appareil (hors forçage).
    var isSettled: Bool { source == .stored || source == .assigned }
}

// Variantes forcées (build Debug seulement : l'implémentation de Release ne force rien).
protocol ExperimentOverrides: Sendable {
    func forcedVariant(of flag: String) -> String?
    func setForcedVariant(_ variant: String?, of flag: String)
}

struct NoExperimentOverrides: ExperimentOverrides {
    func forcedVariant(of flag: String) -> String? { nil }
    func setForcedVariant(_ variant: String?, of flag: String) {}
}

// Groupes tirés sur cet appareil (clé du flag → variante), pour qu'un utilisateur ne change pas de groupe quand son
// identifiant PostHog change (connexion, déconnexion).
protocol ExperimentAssignmentsStore: Sendable {
    var experimentAssignments: [String: String] { get }
    func setExperimentAssignment(_ variant: String, of flag: String)
    func clearExperimentAssignments()
}
