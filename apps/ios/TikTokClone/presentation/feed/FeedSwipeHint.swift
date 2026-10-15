import SwiftUI

// Indication « Balaie vers le haut pour en voir plus » sur la première vidéo du feed (ADR-055), comme TikTok : fond
// assombri, téléphone et main qui glisse. Un toucher la ferme ; le premier défilement aussi (FeedView). Le défilement
// passe au travers : seul un toucher bref est intercepté.
struct FeedSwipeHint: View {
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 28) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let cycle = 1.8
                    let raw = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.white.opacity(0.18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.6), lineWidth: 3))
                            .frame(width: 110, height: 190)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                            .offset(x: 36, y: 60 - raw * 110)
                            .opacity(raw < 0.85 ? 1 : (1 - raw) / 0.15)
                    }
                }
                Text("Balaie vers le haut pour en voir plus")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Touche pour fermer")
        .accessibilityIdentifier("feed.swipeHint")
    }
}
