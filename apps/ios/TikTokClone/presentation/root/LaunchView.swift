import SwiftUI

// Attente de la reprise de session, au lancement. Même fond noir que l'écran de lancement système
// (couleur `LaunchBackground`, `UILaunchScreen` dans project.yml) et que le feed qui suit : pas d'éclair blanc
// entre les trois.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 20) {
                Text("TikTok Clone")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chargement de TikTok Clone")
    }
}
