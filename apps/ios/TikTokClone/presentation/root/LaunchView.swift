import SwiftUI

// Écran de lancement (ADR-055), pendant la reprise de session et au moins 2 s (choix du développeur : il passait en moins
// d'une seconde) : logo et nom de l'app au centre, sur le même fond noir
// que l'écran de lancement système (couleur `LaunchBackground`, `UILaunchScreen` dans project.yml) et que le feed qui
// suit : pas d'éclair blanc entre les trois.
struct LaunchView: View {
    // Durée minimale d'affichage, depuis l'ouverture de l'app (la reprise de session se fait pendant ce temps).
    static let minimumDuration: Duration = .seconds(2)

    // Petite animation (choix du développeur) : la note apparaît en rebondissant et ses échos cyan et rose s'écartent,
    // le nom monte en fondu, puis la note bat doucement jusqu'à la fin du chargement. Rien de tout ça si l'utilisateur
    // a demandé de réduire les animations.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoShown = false
    @State private var echoesSpread = false
    @State private var nameShown = false
    @State private var beating = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 18) {
                AppLogo(size: 76, spread: echoesSpread ? 1 : 0)
                    .scaleEffect(logoShown ? (beating ? 1.08 : 1) : 0.5)
                    .opacity(logoShown ? 1 : 0)
                AppWordmark(size: 30)
                    .opacity(nameShown ? 1 : 0)
                    .offset(y: nameShown ? 0 : 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de TikTok Clone")
        .task { await animate() }
    }

    private func animate() async {
        guard !reduceMotion else {
            logoShown = true
            echoesSpread = true
            nameShown = true
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { logoShown = true }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) { echoesSpread = true }
        withAnimation(.easeOut(duration: 0.45)) { nameShown = true }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { beating = true }
    }
}
