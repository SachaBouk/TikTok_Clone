import SwiftUI

// Étape 6 de l'inscription (ADR-055) : « Balaie vers le haut », téléphone dessiné où les vidéos défilent sous une main.
// Pas de « vidéos personnalisées » : il n'y a pas de personnalisation (ADR-016).
struct SignupTutorialView: View {
    let model: SignupFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Balaie vers le haut")
                .font(.system(size: 34, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            Text("Fais glisser vers le haut pour passer à la vidéo suivante.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer(minLength: 24)
            SwipeDemoPhone()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 24)
            SignupPrimaryButton(title: "Commencer à regarder") { model.finish() }
                .accessibilityIdentifier("signup.tutorial.start")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.viewed(.tutorial) }
    }
}

// Téléphone stylisé : deux « vidéos » (dégradés) défilent vers le haut sous une main qui glisse, en boucle.
private struct SwipeDemoPhone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let videos: [[Color]] = [
        [Color(red: 0.55, green: 0.67, blue: 0.78), Color(red: 0.98, green: 0.93, blue: 0.75), Color(red: 0.35, green: 0.36, blue: 0.32)],
        [Color(red: 0.86, green: 0.78, blue: 0.86), Color(red: 0.99, green: 0.55, blue: 0.35), Color(red: 0.22, green: 0.14, blue: 0.13)],
        [Color(red: 0.15, green: 0.95, blue: 0.93), Color(red: 0.2, green: 0.25, blue: 0.5), Color(red: 1, green: 0.17, blue: 0.33)],
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            // Cycle de 2,4 s : 1 s d'immobilité, puis le glissement (main et vidéo) en 1,4 s.
            let cycle = 2.4
            let time = context.date.timeIntervalSinceReferenceDate
            let index = Int(time / cycle) % Self.videos.count
            let local = time.truncatingRemainder(dividingBy: cycle)
            let raw = reduceMotion ? 0 : max(0, (local - 1) / 1.4)
            let progress = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
            GeometryReader { proxy in
                let height = proxy.size.height
                ZStack {
                    VStack(spacing: 0) {
                        video(Self.videos[index]).frame(height: height)
                        video(Self.videos[(index + 1) % Self.videos.count]).frame(height: height)
                    }
                    .offset(y: -progress * height)
                    .frame(height: height, alignment: .top)
                    .clipped()
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                        .offset(x: 40, y: height * 0.22 - progress * height * 0.35)
                        .opacity(raw > 0.85 ? (1 - raw) / 0.15 : 1)
                }
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.primary, lineWidth: 8))
        .frame(maxHeight: 420)
        .accessibilityHidden(true)
    }

    private func video(_ colors: [Color]) -> some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
