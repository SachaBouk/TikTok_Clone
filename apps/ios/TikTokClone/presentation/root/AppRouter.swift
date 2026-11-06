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
    // Collection ouverte par un lien d'app (tiktokclone://collections/<id>, ADR-072), dans une feuille.
    var presentedCollection: CollectionRoute?

    // Menu ☰ de son profil (ADR-057), panneau par-dessus les onglets.
    var isProfileMenuOpen = false
    // Balayage vers le profil d'un auteur en cours (`authorProfileSwipe`) : barres du haut des lecteurs masquées.
    var isSwipingToProfile = false
    // Toucher l'onglet Accueil alors qu'il est déjà affiché (comme TikTok) : le feed affiché se recharge. Chaque toucher
    // incrémente le compteur ; `isHomeRefreshing` pendant le rechargement (flèche qui tourne dans la barre d'onglets,
    // deux points à la place de la loupe).
    var homeRefreshRequests = 0
    var isHomeRefreshing = false
    // Pareil pour l'onglet Amis (ADR-054) : flèche dans la barre, deux points en haut à droite.
    var friendsRefreshRequests = 0
    var isFriendsRefreshing = false

    // Visionneuse de stories (ADR-051) : les stories d'un compte, puis celles des suivants (rangée).
    struct StoriesRoute: Identifiable, Equatable {
        let id = UUID()
        let authors: [UserSummary]
        let startAuthor: Int
        let source: StorySource
    }

    var presentedStories: StoriesRoute?
    // Création en plein écran (bouton « + », ADR-062), dans le mode demandé (« + » de « Ta story » : Story).
    struct CreationRoute: Identifiable, Equatable {
        let id = UUID()
        let mode: PublishDraftViewModel.Mode
        // Brouillon rouvert (ADR-065) : l'éditeur s'ouvre sur son montage.
        var draft: VideoDraft?
        // « Importer » de son profil vide (ADR-070) : la galerie s'ouvre aussitôt par-dessus la caméra.
        var opensGallery = false
    }

    var presentedCreation: CreationRoute?
    // Incrémenté à chaque vidéo publiée depuis la création : l'onglet Profil s'ouvre (publication en cours).
    var publishedFromCreation = 0

    func openCreation(mode: PublishDraftViewModel.Mode = .video, draft: VideoDraft? = nil, opensGallery: Bool = false) {
        guard presentedCreation == nil else { return }
        presentedCreation = CreationRoute(mode: mode, draft: draft, opensGallery: opensGallery)
    }

    func openStories(_ authors: [UserSummary], startAuthor: Int = 0, source: StorySource) {
        guard !authors.isEmpty else { return }
        presentedStories = StoriesRoute(authors: authors, startAuthor: startAuthor, source: source)
    }

    // Live commun (ADR-079, SDK d'echimine) : liste des lives en cours de toutes les apps membres (icône « LIVE »),
    // écran de lancement (mode Live de la caméra), ou un live par son identifiant (lien d'app, carte d'un message).
    // Présenté par-dessus tout le reste, à la racine : la vidéo seule, la visionneuse de stories et la création sont fermées.
    struct LiveRoute: Identifiable, Equatable {
        enum Content: Equatable {
            case list
            case launch
            case watch(liveID: String, source: LiveSource)
        }

        let id = UUID()
        let content: Content
    }

    var presentedLive: LiveRoute?

    func openLive(_ liveID: String, source: LiveSource) {
        presentLive(.watch(liveID: liveID, source: source))
    }

    func startLive() {
        presentLive(.launch)
    }

    // Icône « LIVE » de l'accueil.
    func openLiveFeed() {
        presentLive(.list)
    }

    private func presentLive(_ content: LiveRoute.Content) {
        guard presentedLive == nil else { return }
        let route = LiveRoute(content: content)
        guard presentedVideo != nil || presentedStories != nil || presentedCreation != nil else {
            presentedLive = route
            return
        }
        // Fermer un plein écran et en présenter un autre dans la même mise à jour échoue : le live attend la fermeture.
        presentedVideo = nil
        presentedStories = nil
        presentedCreation = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if self?.presentedLive == nil { self?.presentedLive = route }
        }
    }

    // Liste des conversations de l'onglet Messages à l'écran (posé par MainTabView) : pas de bandeau de message (ADR-078).
    var isInboxListShown = false

    // Page d'un onglet ouverte par un bandeau (ADR-078) : l'onglet est choisi, sa pile vidée puis la page poussée
    // (MainTabView), après la fermeture des écrans par-dessus.
    struct TabRequest: Identifiable, Equatable {
        enum Page: Equatable {
            case conversation(Conversation)
            case activity
            case publications
        }

        let id = UUID()
        let page: Page
        // Un écran plein écran ou une feuille vient d'être fermé : attendre la fin de l'animation.
        let afterDismissal: Bool
    }

    var tabRequest: TabRequest?

    // Toucher d'un bandeau (ADR-078). `me` : son compte, pour ses stories.
    func open(_ target: InAppBanner.Target, me: UserSummary?) {
        switch target {
        case .video(let id):
            presentedVideo = VideoRoute(id: id)
        case .profile(let username):
            presentedProfile = ProfileSheetRoute(username: username)
        case .live(let id):
            openLive(id, source: .activity)
        case .ownStories:
            if let me { openStories([me], source: .profile) }
        case .conversation(let conversation):
            openTab(.conversation(conversation))
        case .activity:
            openTab(.activity)
        case .publications:
            openTab(.publications)
        }
    }

    private func openTab(_ page: TabRequest.Page) {
        let covered = presentedVideo != nil || presentedStories != nil || presentedProfile != nil || presentedCollection != nil
        presentedVideo = nil
        presentedStories = nil
        presentedProfile = nil
        presentedCollection = nil
        isProfileMenuOpen = false
        tabRequest = TabRequest(page: page, afterDismissal: covered)
    }

    // Onboarding animé affiché (ADR-075) : plein écran du premier lancement, ou fin du parcours dans la feuille d'un
    // invité. Le feed chargé derrière ne doit pas jouer (son par-dessus l'onboarding, bug rencontré).
    var isOnboardingShown = false

    // Un écran plein écran couvre les onglets : le feed est en pause.
    var coversTabs: Bool {
        presentedVideo != nil || presentedStories != nil || presentedLive != nil || presentedCreation != nil || isOnboardingShown
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
        if let collectionID = CollectionLink.id(from: url) {
            presentedCollection = CollectionRoute(id: collectionID)
            return true
        }
        guard let videoID = VideoLink.videoID(from: url) else { return false }
        presentedVideo = VideoRoute(id: videoID)
        return true
    }
}
