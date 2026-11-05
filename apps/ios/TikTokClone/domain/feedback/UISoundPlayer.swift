import Foundation

// Sons de l'interface (ADR-075) : sons courts, originaux, synthétisés par l'app (aucun fichier audio).
enum UISound: String, CaseIterable, Sendable {
    // Toucher d'un bouton.
    case tap
    // Choix d'une réponse, d'une pastille.
    case select
    // Interrupteur, bascule Annuel / Mensuel.
    case toggle
    // Passage d'un écran ou d'une vidéo à l'autre.
    case whoosh
    // Cœur, j'aime.
    case pop
    // Vitesse ×2.
    case speedUp
    // Petit tic (segment, critère coché).
    case tick
    // Réussite (accord).
    case success
    // Fête (arpège et scintillement).
    case celebrate
    // Refus.
    case error
    // Bulle de la mascotte qui s'écrit.
    case typing
}

// Lecteur des sons de l'interface. `activate` avant usage (session audio qui respecte le mode silencieux),
// `deactivate` après (la session des vidéos revient).
@MainActor
protocol UISoundPlayer: AnyObject {
    func activate()
    func deactivate()
    func play(_ sound: UISound)
}

// Aucun son : tests, aperçus.
@MainActor
final class SilentSoundPlayer: UISoundPlayer {
    private(set) var played: [UISound] = []
    func activate() {}
    func deactivate() {}
    func play(_ sound: UISound) { played.append(sound) }
}
