import Foundation
import Observation

// Navigation déclenchée de l'extérieur : liens d'app (tiktokclone://videos/<id>), puis notifications push ; et écrans
// plein écran ouverts de partout (vidéo seule, stories, live).
@MainActor
@Observable
final class AppRouter {
    struct VideoRoute: Identifiable, Equatable {
        let id: String
    }

    var presentedVideo: VideoRoute?

    // Profil ouvert par un lien d'app (tiktokclone://users/<pseudo>, « Partager le profil », ADR-056), dans une feuille.
    struct ProfileSheetRoute: Identifiable, Equatable {
        let username: String
        var id: String { username }
    }

    var presentedProfile: ProfileSheetRoute?

    // Menu ☰ de son profil (ADR-057), panneau par-dessus les onglets.
    var isProfileMenuOpen = false
    // Toucher l'onglet Accueil alors qu'il est déjà affiché (comme TikTok) : le feed affiché se recharge. Chaque toucher
    // incrémente le compteur ; `isHomeRefreshing` pendant le rechargement (flèche qui tourne dans la barre d'onglets,
    // deux points à la place de la loupe).
    var homeRefreshRequests = 0
    var isHomeRefreshing = false

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

    // Live (ADR-053) : le lancer (son auteur) ou le regarder. Présenté par-dessus tout le reste, à la racine : la vidéo
    // seule et la visionneuse de stories sont fermées.
    struct LiveRoute: Identifiable, Equatable {
        let id = UUID()
        let mode: LiveRoomModel.Mode
    }

    var presentedLive: LiveRoute?

    func openLive(_ liveID: String, source: LiveSource) {
        presentLive(.viewer(liveID: liveID, source: source))
    }

    func startLive(title: String) {
        presentLive(.host(title: title))
    }

    private func presentLive(_ mode: LiveRoomModel.Mode) {
        guard presentedLive == nil else { return }
        let route = LiveRoute(mode: mode)
        guard presentedVideo != nil || presentedStories != nil else {
            presentedLive = route
            return
        }
        // Fermer un plein écran et en présenter un autre dans la même mise à jour échoue : le live attend la fermeture.
        presentedVideo = nil
        presentedStories = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if self?.presentedLive == nil { self?.presentedLive = route }
        }
    }

    // Un écran plein écran couvre les onglets : le feed est en pause.
    var coversTabs: Bool {
        presentedVideo != nil || presentedStories != nil || presentedLive != nil
    }

    // Renvoie false si le lien n'est pas reconnu.
    @discardableResult
    func open(_ url: URL) -> Bool {
        if let liveID = LiveLink.liveID(from: url) {
            openLive(liveID, source: .link)
            return true
        }
        if let username = ProfileLink.username(from: url) {
            presentedProfile = ProfileSheetRoute(username: username)
            return true
        }
        guard let videoID = VideoLink.videoID(from: url) else { return false }
        presentedVideo = VideoRoute(id: videoID)
        return true
    }
}
