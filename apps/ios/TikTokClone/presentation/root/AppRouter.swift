import Foundation
import Observation

// Navigation déclenchée de l'extérieur : liens d'app (tiktokclone://videos/<id>), puis notifications push ; et écrans
// plein écran ouverts de partout (vidéo seule, stories).
@MainActor
@Observable
final class AppRouter {
    struct VideoRoute: Identifiable, Equatable {
        let id: String
    }

    var presentedVideo: VideoRoute?

    // Visionneuse de stories (ADR-051) : les stories d'un compte, puis celles des suivants (rangée).
    struct StoriesRoute: Identifiable, Equatable {
        let id = UUID()
        let authors: [UserSummary]
        let startAuthor: Int
        let source: StorySource
    }

    var presentedStories: StoriesRoute?
    // « + » de « Ta story » : l'onglet Publier s'ouvre en mode Story (lu puis remis à nil par l'onglet).
    var requestedPublishMode: PublishDraftViewModel.Mode?

    func openStories(_ authors: [UserSummary], startAuthor: Int = 0, source: StorySource) {
        guard !authors.isEmpty else { return }
        presentedStories = StoriesRoute(authors: authors, startAuthor: startAuthor, source: source)
    }

    // Renvoie false si le lien n'est pas reconnu.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let videoID = VideoLink.videoID(from: url) else { return false }
        presentedVideo = VideoRoute(id: videoID)
        return true
    }
}
