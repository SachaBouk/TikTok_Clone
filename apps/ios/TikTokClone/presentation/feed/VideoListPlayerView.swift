import SwiftUI

// Lecteur vertical ouvert depuis une grille (profil, historique), sur la vidéo touchée. Même page que le
// feed ; la liste s'arrête à sa fin. Retour par le bouton natif de la barre de navigation.
struct VideoListPlayerView: View {
    let route: VideoPlayerRoute
    let container: AppContainer

    var body: some View {
        FeedView(
            viewModel: container.makeVideoListViewModel(route),
            pool: container.playerPool,
            interactions: container.videoInteractions,
            container: container,
            isTabActive: true,
            allowsRefresh: false
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
