import SwiftUI
import UIKit

// Icône d'un onglet de feed (Accueil, Amis) pendant le rechargement demandé par un toucher sur l'onglet déjà affiché
// (comme TikTok, d'après une vidéo) : l'icône de l'onglet rétrécit, une flèche circulaire grandit à sa place et tourne
// (un tour en 0,8 s) tant que le feed se recharge, puis rétrécit et l'icône revient. La barre d'onglets native n'anime
// pas les symboles (`symbolEffect` y est ignoré) : chaque étape est dessinée en image (`TabRefreshIcon.image`), ~30 fois
// par seconde.
enum TabRefreshIcon: Equatable {
    // Le symbole de l'onglet, géré par la barre (plein une fois sélectionné).
    case standard
    // Une étape dessinée : symbole, rotation en degrés, échelle de 0 à 1.
    case frame(symbol: String, angle: Double, scale: Double)

    static let shrink: TimeInterval = 0.1
    static let turn: TimeInterval = 0.8
    static let frameInterval: Duration = .milliseconds(33)

    // Étape à `elapsed` secondes du début ; `endedFor` : secondes depuis la fin du rechargement (nil s'il dure encore).
    // `symbol` : l'icône pleine de l'onglet (« house.fill », « person.2.fill »).
    static func at(elapsed: TimeInterval, endedFor: TimeInterval?, symbol: String) -> TabRefreshIcon {
        if let ended = endedFor {
            if ended >= 2 * shrink { return .standard }
            return ended < shrink
                ? .frame(symbol: "arrow.clockwise", angle: angle(elapsed), scale: 1 - ended / shrink)
                : .frame(symbol: symbol, angle: 0, scale: (ended - shrink) / shrink)
        }
        if elapsed < shrink { return .frame(symbol: symbol, angle: 0, scale: 1 - elapsed / shrink) }
        return .frame(symbol: "arrow.clockwise", angle: angle(elapsed), scale: min(1, (elapsed - shrink) / shrink))
    }

    // La fin attend que la flèche ait grandi : l'icône ne revient pas avant que la flèche se soit montrée.
    static func canEnd(elapsed: TimeInterval) -> Bool {
        elapsed >= 2 * shrink
    }

    private static func angle(_ elapsed: TimeInterval) -> Double {
        max(0, elapsed - shrink) / turn * 360
    }

    // Image d'une étape, en gabarit (teinte de la barre), toujours de la même taille : la barre ne bouge pas.
    @MainActor
    static func image(symbol: String, angle: Double, scale: Double) -> UIImage {
        let canvas = CGSize(width: 30, height: 30)
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        guard let symbolImage = UIImage(systemName: symbol, withConfiguration: configuration) else { return UIImage() }
        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            let cg = context.cgContext
            cg.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            cg.rotate(by: angle * .pi / 180)
            cg.scaleBy(x: max(scale, 0.001), y: max(scale, 0.001))
            let size = symbolImage.size
            symbolImage.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
