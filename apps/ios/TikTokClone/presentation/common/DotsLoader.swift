import SwiftUI

// Indicateur d'attente à deux points rose et cyan, aux couleurs du logo maison (ADR-055) : les points échangent leur
// place en continu. Sans animation si « Réduire les animations » est activé. Avec `phase` (tirer pour actualiser), les
// points sont figés à cette étape de l'échange (1 = un échange complet), au lieu de suivre l'horloge.
struct DotsLoader: View {
    var size: CGFloat = 12
    var colors: (Color, Color) = (.brandPink, .brandCyan)
    var phase: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || phase != nil)) { context in
            // Une demi-période par échange, avec un aller-retour adouci.
            let period = 0.9
            let clock = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let step = phase.map { $0.truncatingRemainder(dividingBy: 1) } ?? clock
            let progress = reduceMotion ? 0 : (1 - cos(step * 2 * .pi)) / 2
            let spread = size * 0.75
            ZStack {
                Circle().fill(colors.1).frame(width: size, height: size)
                    .offset(x: spread * (1 - 2 * progress))
                    .zIndex(progress > 0.5 ? 1 : 0)
                Circle().fill(colors.0).frame(width: size, height: size)
                    .offset(x: -spread * (1 - 2 * progress))
                    .zIndex(progress > 0.5 ? 0 : 1)
            }
            .frame(width: size * 2.6, height: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Chargement")
    }
}
