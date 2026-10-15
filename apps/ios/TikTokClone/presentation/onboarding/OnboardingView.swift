import SwiftUI

// Onboarding du premier lancement (ADR-055) : l'introduction « Tout commence sur TikTok Clone. » (2 s, ou un toucher),
// puis l'écran « Connexion » avec « Continuer sans compte ».
struct OnboardingView: View {
    let container: AppContainer
    let finish: () -> Void
    @State private var showsIntro = true

    var body: some View {
        ZStack {
            if showsIntro {
                OnboardingIntro()
                    .transition(.opacity)
                    .onTapGesture { advance() }
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        advance()
                    }
            } else {
                AuthFlowView(container: container, source: .onboarding, skip: finish)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showsIntro)
    }

    private func advance() {
        showsIntro = false
    }
}

// « Tout commence sur TikTok Clone. » en haut, logo et nom en bas.
private struct OnboardingIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tout commence\nsur TikTok Clone.")
                .font(.system(size: 40, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 60)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                AppLogo(size: 64, foreground: .primary)
                AppWordmark(size: 28, foreground: .primary)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Touche pour continuer")
        .accessibilityIdentifier("onboarding.intro")
    }
}
