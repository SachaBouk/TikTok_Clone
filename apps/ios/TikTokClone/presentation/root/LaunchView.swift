import SwiftUI

// Écran de lancement (ADR-055), pendant la reprise de session : logo et nom de l'app au centre, sur le même fond noir
// que l'écran de lancement système (couleur `LaunchBackground`, `UILaunchScreen` dans project.yml) et que le feed qui
// suit : pas d'éclair blanc entre les trois.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 18) {
                AppLogo(size: 76)
                AppWordmark(size: 30)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de TikTok Clone")
    }
}
