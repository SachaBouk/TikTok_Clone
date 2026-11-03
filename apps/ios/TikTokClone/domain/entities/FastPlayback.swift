import Foundation

// Vitesse ×2 du lecteur vidéo, comme TikTok (choix du développeur, d'après des captures) :
// - appui long sur un côté de la vidéo (le milieu est réservé) : lecture en ×2 tant que le doigt reste posé ;
// - en glissant vers le bas pendant l'appui, puis en relâchant : la vitesse ×2 est verrouillée, pour toutes les vidéos ;
// - verrouillée, un appui long lit à vitesse normale ; glisser vers le bas puis relâcher la déverrouille.
// Gardée jusqu'à la relance de l'app (et oubliée à la déconnexion), dans tous les lecteurs vidéo (ni stories ni lives).
// La vitesse choisie dans le menu de la vidéo (ADR-067) est le même réglage : verrouiller le ×2 revient à choisir 2.0×.
struct FastPlayback: Equatable, Sendable {
    static let fastRate: Float = 2
    // Distance vers le bas, en points, au-delà de laquelle relâcher verrouille (ou déverrouille).
    static let lockDistance: Double = 50
    // Part de la largeur de chaque côté où l'appui long accélère ; le reste (le milieu) est réservé.
    static let sideFraction: Double = 0.3

    // Appui en cours ; `isArmed` : le doigt est descendu assez bas pour que relâcher change le verrouillage.
    struct Hold: Equatable, Sendable {
        var isArmed = false
    }

    // Bandeau du bas pendant l'appui.
    struct Hint: Equatable, Sendable {
        let text: String
        // Doigt descendu : bandeau blanc avec un cadenas ; sinon, bandeau sombre avec les flèches vers le bas.
        let isArmed: Bool
    }

    // Message affiché en haut un instant : changement de verrouillage, défilement automatique (ADR-067).
    enum Notice: Equatable, Sendable {
        case locked, unlocked
        case autoScrollOn, autoScrollOff

        var text: String {
            switch self {
            case .locked: "Verrouillée à la vitesse accélérée ×2"
            case .unlocked: "Retour à la vitesse normale"
            case .autoScrollOn: "La prochaine publication s'affichera automatiquement"
            case .autoScrollOff: "Fais défiler jusqu'à la publication suivante"
            }
        }

        // Nil : texte seul.
        var systemImage: String? {
            switch self {
            case .locked: "lock.fill"
            case .unlocked: "lock.open"
            case .autoScrollOn, .autoScrollOff: nil
            }
        }
    }

    private(set) var speed: PlaybackSpeed = .normal
    private(set) var hold: Hold?

    // Verrouillée en ×2 (glisser vers le bas pendant l'appui, ou 2.0× choisi dans le menu).
    var isLocked: Bool { speed == .double }

    // Vitesse de lecture : la vitesse choisie ; pendant l'appui, ×2, ou vitesse normale si le ×2 est verrouillé.
    var rate: Float {
        guard hold != nil else { return Float(speed.rawValue) }
        return isLocked ? 1 : Self.fastRate
    }

    var hint: Hint? {
        guard let hold else { return nil }
        let text =
            switch (isLocked, hold.isArmed) {
            case (false, false): "Glisse en bas pour garder la vitesse ×2"
            case (false, true): "Relâche pour bloquer la vitesse ×2"
            case (true, false): "Glisse en bas pour la vitesse normale"
            case (true, true): "Relâche pour aller à vitesse normale"
            }
        return Hint(text: text, isArmed: hold.isArmed)
    }

    // L'appui long accélère seulement sur les côtés de la vidéo.
    static func isSide(x: Double, width: Double) -> Bool {
        guard width > 0 else { return false }
        return x < width * sideFraction || x > width * (1 - sideFraction)
    }

    mutating func begin() {
        hold = Hold()
    }

    // `translation` : déplacement vertical du doigt depuis le début de l'appui (positif vers le bas). Remonter désarme.
    mutating func drag(translation: Double) {
        guard hold != nil else { return }
        hold?.isArmed = translation >= Self.lockDistance
    }

    // Doigt relâché : le verrouillage change si le doigt était descendu ; renvoie alors le message à afficher.
    @discardableResult
    mutating func end() -> Notice? {
        guard let hold else { return nil }
        self.hold = nil
        guard hold.isArmed else { return nil }
        speed = isLocked ? .normal : .double
        return isLocked ? .locked : .unlocked
    }

    // Vitesse choisie dans le menu de la vidéo, ou dans l'affichage allégé.
    mutating func setSpeed(_ speed: PlaybackSpeed) {
        self.speed = speed
    }

    // Appui interrompu (app en arrière-plan, autre geste) : rien ne change.
    mutating func cancel() {
        hold = nil
    }
}

// Vitesses du menu d'une vidéo (ADR-067), comme TikTok.
enum PlaybackSpeed: Double, CaseIterable, Sendable {
    case half = 0.5
    case normal = 1
    case oneAndHalf = 1.5
    case double = 2

    // « 0.5× » dans le menu, comme TikTok.
    var label: String {
        String(format: "%.1f×", rawValue)
    }

    // Pastille de l'affichage allégé : « 1× », « 1.5× ».
    var shortLabel: String {
        rawValue == rawValue.rounded() ? "\(Int(rawValue))×" : "\(rawValue)×"
    }

    // Toucher la vitesse de l'affichage allégé : la suivante, puis retour à 0.5×.
    var next: PlaybackSpeed {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
