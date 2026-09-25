import Foundation
import TikTokAPI

// Injection de dépendances manuelle (ADR-002) : seul endroit où les implémentations de la couche data/
// sont choisies. Les vues demandent leurs ViewModels ici ; les ViewModels ne voient que des protocoles.
@MainActor
final class AppContainer {
    let session: SessionStore
    // Lecteurs vidéo partagés par les écrans qui lisent des vidéos (feed, vidéo seule, puis grilles).
    let playerPool = AVPlayerPool()
    let router = AppRouter()
    // État des interactions partagé par tous les écrans vidéo (un like dans l'un se voit dans l'autre).
    let videoInteractions: VideoInteractionsModel
    private let auth: any AuthRepository
    private let profiles: any ProfileRepository
    private let feed: any FeedRepository
    private let viewHistory: any ViewHistoryRepository
    private let interactions: any InteractionRepository

    init(configuration: AppConfiguration, tokenStore: any TokenStore = KeychainTokenStore()) {
        // Le rafraîchissement passe par un client sans AuthMiddleware, sinon il se rappellerait lui-même.
        let refreshClient = APIClientFactory.make(baseURL: configuration.apiBaseURL)
        let expiry = SessionExpiryRelay()
        let refresher = TokenRefresher(
            store: tokenStore,
            refresh: RemoteTokenRefresh.make(client: refreshClient),
            onSessionExpired: { await expiry.notify() }
        )
        let client = APIClientFactory.make(baseURL: configuration.apiBaseURL, middlewares: [AuthMiddleware(refresher: refresher)])

        auth = RemoteAuthRepository(client: client, store: tokenStore)
        profiles = RemoteProfileRepository(client: client)
        feed = RemoteFeedRepository(client: client)
        viewHistory = RemoteViewHistoryRepository(client: client)
        interactions = RemoteInteractionRepository(client: client)
        session = SessionStore(
            restoreSession: RestoreSessionUseCase(auth: auth, profiles: profiles),
            logout: LogoutUseCase(auth: auth)
        )
        expiry.session = session
        videoInteractions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactions),
            setFollow: SetFollowUseCase(interactions: interactions),
            recordShare: ShareVideoUseCase(interactions: interactions),
            session: session
        )
    }

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(login: LoginUseCase(auth: auth, profiles: profiles), session: session)
    }

    func makeRegisterViewModel() -> RegisterViewModel {
        RegisterViewModel(register: RegisterUseCase(auth: auth, profiles: profiles), session: session)
    }

    func makeFeedViewModel() -> FeedViewModel {
        FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: feed),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session
        )
    }

    func makeCommentsViewModel(video: FeedVideo, onCountChange: @escaping (Int) -> Void) -> CommentsViewModel {
        CommentsViewModel(
            video: video,
            loadComments: LoadCommentsUseCase(interactions: interactions),
            addComment: AddCommentUseCase(interactions: interactions),
            deleteComment: DeleteCommentUseCase(interactions: interactions),
            session: session,
            onCountChange: onCountChange
        )
    }

    func makeVideoDetailViewModel(videoID: String) -> VideoDetailViewModel {
        VideoDetailViewModel(
            videoID: videoID,
            loadVideo: LoadVideoUseCase(feed: feed),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session
        )
    }

    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(getMyProfile: GetMyProfileUseCase(profiles: profiles), session: session)
    }
}

// Relaie la fin de session détectée par la couche data/ (refresh token refusé) vers la session de l'app,
// créée après le client : casse la dépendance circulaire à la construction.
@MainActor
final class SessionExpiryRelay {
    weak var session: SessionStore?

    func notify() {
        session?.sessionExpired()
    }
}
