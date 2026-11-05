import Foundation

// Variantes forcées des expériences A/B (ADR-077), dans le build Debug seulement : clé `experiment.<flag>` de
// UserDefaults, écrite par l'écran « Expériences » des paramètres, ou passée en argument de lancement
// (`-experiment.feed-swipe-hint hidden` : le domaine des arguments l'emporte alors sur l'écran). En Release, rien
// n'est jamais forcé.
struct UserDefaultsExperimentOverrides: ExperimentOverrides, @unchecked Sendable {
    // UserDefaults est sûr entre fils d'exécution (documenté par Apple), mais pas déclaré Sendable.
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(_ flag: String) -> String { "experiment.\(flag)" }

    func forcedVariant(of flag: String) -> String? {
        #if DEBUG
            defaults.string(forKey: Self.key(flag))
        #else
            nil
        #endif
    }

    func setForcedVariant(_ variant: String?, of flag: String) {
        #if DEBUG
            if let variant { defaults.set(variant, forKey: Self.key(flag)) } else { defaults.removeObject(forKey: Self.key(flag)) }
        #endif
    }
}
