import Foundation

// Vitesse ×2 du lecteur vidéo, comme TikTok (choix du développeur, d'après des captures) :
// - appui long sur un côté de la vidéo (le milieu est réservé) : lecture en ×2 tant que le doigt reste posé ;
// - en glissant vers le bas pendant l'appui, puis en relâchant : la vitesse ×2 est verrouillée, pour toutes les vidéos ;
// - verrouillée, un appui long lit à vitesse normale ; glisser vers le bas puis relâcher la déverrouille.
// Gardée jusqu'à la relance de l'app (et oubliée à la déconnexion), dans tous les lecteurs vidéo (ni stories ni lives).
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

    // Message affiché en haut un instant après un changement de verrouillage.
    enum Notice: Equatable, Sendable {
        case locked, unlocked

        var text: String {
            switch self {
            case .locked: "Verrouillée à la vitesse accélérée ×2"
            case .unlocked: "Retour à la vitesse normale"
            }
        }

        var systemImage: String {
            switch self {
            case .locked: "lock.fill"
            case .unlocked: "lock.open"
            }
        }
    }

    private(set) var isLocked = false
    private(set) var hold: Hold?

    // Vitesse de lecture : l'appui inverse l'état verrouillé (×2 sans verrou, vitesse normale avec).
    var rate: Float {
        (hold != nil) != isLocked ? Self.fastRate : 1
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
        isLocked.toggle()
        return isLocked ? .locked : .unlocked
    }

    // Appui interrompu (app en arrière-plan, autre geste) : rien ne change.
    mutating func cancel() {
        hold = nil
    }
}
