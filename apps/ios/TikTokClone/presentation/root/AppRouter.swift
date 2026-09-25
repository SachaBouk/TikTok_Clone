import Foundation
import Observation

// Navigation déclenchée de l'extérieur : liens d'app (tiktokclone://videos/<id>), puis notifications push.
@MainActor
@Observable
final class AppRouter {
    struct VideoRoute: Identifiable, Equatable {
        let id: String
    }

    var presentedVideo: VideoRoute?

    // Renvoie false si le lien n'est pas reconnu.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let videoID = VideoLink.videoID(from: url) else { return false }
        presentedVideo = VideoRoute(id: videoID)
        return true
    }
}
