import SwiftUI

// Indication « Balaie vers le haut pour en voir plus » sur la première vidéo du feed (ADR-055), comme TikTok : fond
// assombri, téléphone et main qui glisse. Un toucher la ferme ; balayer vers le haut la ferme et passe à la vidéo
// suivante (`next`). Posée par-dessus le feed, elle prend les gestes : le défilement ne passait pas au travers (bug
// rencontré, l'indication restait affichée).
struct FeedSwipeHint: View {
    let dismiss: () -> Void
    let next: () -> Void
    // Distance vers le haut au-delà de laquelle un glissement passe à la vidéo suivante.
    static let swipeDistance: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false

    // Redessinée comme TikTok (ADR-075) : téléphone translucide avec son encoche et un triangle de lecture, la vidéo
    // qui monte dedans, une grande main qui glisse ; apparition en fondu, vibration au balayage.
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 30) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let cycle = 1.9
                    let raw = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                    let eased = raw < 0.75 ? (1 - cos(raw / 0.75 * .pi)) / 2 : 1
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.white.opacity(0.16))
                            .overlay {
                                // La vidéo du téléphone monte avec la main : un seul triangle au centre au repos ; il sort par
                                // le haut pendant que le suivant entre par le bas (écartés de la hauteur du téléphone,
                                // coupés par l'écran).
                                VStack(spacing: 0) {
                                    Image(systemName: "play.fill").font(.system(size: 38)).frame(height: 220)
                                    Image(systemName: "play.fill").font(.system(size: 38)).frame(height: 220)
                                }
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(height: 220, alignment: .top)
                                .offset(y: -eased * 220)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.55), lineWidth: 4))
                            .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.55)).frame(width: 46, height: 10).padding(.top, 10) }
                            .frame(width: 124, height: 220)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 78))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                            .rotationEffect(.degrees(-8 + eased * 10))
                            .offset(x: 44, y: 70 - eased * 130)
                            .opacity(raw < 0.85 ? 1 : (1 - raw) / 0.15)
                    }
                }
                // Animation : décor pour VoiceOver (ADR-076).
                .accessibilityHidden(true)
                Text("Balaie vers le haut pour en voir plus")
                    .font(.system(size: 30, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .padding(.horizontal, 32)
            }
            .scaleEffect(shown ? 1 : 0.85)
        }
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.5)) { shown = true } }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -Self.swipeDistance {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    next()
                } else {
                    dismiss()
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isButton, .isModal])
        .accessibilityHint("Touche deux fois pour fermer")
        // Équivalent du balayage (ADR-076).
        .accessibilityAction(named: "Vidéo suivante", next)
        .accessibilityScrollAction { edge in if edge == .bottom { next() } }
        .accessibilityIdentifier("feed.swipeHint")
    }
}
