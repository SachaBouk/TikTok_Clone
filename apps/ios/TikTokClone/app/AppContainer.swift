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
    // Publications en cours, partagées par toute l'app (l'envoi continue hors de l'onglet « Publier »).
    let publishing: PublishingModel
    // Centre d'activité : badge et notifications, suivis en direct.
    let activity: ActivityModel
    // Messagerie : badges, conversations et demandes, suivis en direct.
    let messaging: MessagingModel
    let realtime: RealtimeCoordinator
    // Mesure d'audience et tests A/B (ADR-013), après consentement.
    let analytics: AnalyticsModel
    // Portefeuille de jetons et achats (ADR-009).
    let wallet: WalletModel
    private let auth: any AuthRepository
    private let profiles: any ProfileRepository
    private let feed: any FeedRepository
    private let viewHistory: any ViewHistoryRepository
    private let interactions: any InteractionRepository
    private let relationships: any RelationshipRepository
    private let reports: any ReportRepository
    private let videoLists: any VideoListRepository
    private let uploads: any UploadStore
    private let activityRepository: any ActivityRepository
    private let messagingRepository: any MessagingRepository
    private let walletRepository: any WalletRepository

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
        relationships = RemoteRelationshipRepository(client: client)
        reports = RemoteReportRepository(client: client)
        videoLists = RemoteVideoListRepository(client: client)
        let videos = RemoteVideoPublishingRepository(client: client)
        let uploads = FileUploadStore()
        self.uploads = uploads
        session = SessionStore(
            restoreSession: RestoreSessionUseCase(auth: auth, profiles: profiles),
            logout: LogoutUseCase(auth: auth)
        )
        expiry.session = session
        let analyticsService: any AnalyticsService = configuration.analytics.map { PostHogAnalyticsService(configuration: $0) }
            ?? LoggingAnalyticsService()
        analytics = AnalyticsModel(service: analyticsService, preferences: UserDefaultsPreferencesStore())
        videoInteractions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactions),
            setFollow: SetFollowUseCase(interactions: interactions),
            recordShare: ShareVideoUseCase(interactions: interactions),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            session: session,
            analytics: analytics
        )
        publishing = PublishingModel(
            createPublication: CreatePublicationUseCase(store: uploads),
            uploadVideo: UploadVideoUseCase(videos: videos, transport: URLSessionPartUploader(), store: uploads),
            pendingUploads: PendingUploadsUseCase(store: uploads),
            cancelUpload: CancelUploadUseCase(videos: videos, store: uploads),
            loadPendingVideos: LoadPendingVideosUseCase(videos: videos),
            loadVideo: LoadOwnVideoUseCase(videos: videos),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            session: session,
            analytics: analytics
        )
        let activityRepository = RemoteActivityRepository(client: client)
        self.activityRepository = activityRepository
        activity = ActivityModel(
            loadGroups: LoadActivityGroupsUseCase(activity: activityRepository, actorRelationships: LoadActorRelationshipsUseCase(relationships: relationships)),
            loadActorRelationships: LoadActorRelationshipsUseCase(relationships: relationships),
            countUnread: CountUnreadActivityUseCase(activity: activityRepository),
            markRead: MarkActivityReadUseCase(activity: activityRepository),
            session: session
        )
        let channel = WebSocketRealtimeChannel(
            url: configuration.realtimeURL,
            sockets: URLSessionWebSocketFactory(),
            accessToken: { await refresher.validAccessToken() },
            refreshToken: { await refresher.refreshTokens(replacing: $0)?.accessToken }
        )
        let messagingRepository = RemoteMessagingRepository(client: client)
        self.messagingRepository = messagingRepository
        messaging = MessagingModel(
            loadConversations: LoadConversationsUseCase(messaging: messagingRepository),
            loadRequests: LoadMessageRequestsUseCase(messaging: messagingRepository),
            loadConversation: LoadConversationUseCase(messaging: messagingRepository),
            countUnread: CountUnreadMessagesUseCase(messaging: messagingRepository),
            answerRequest: AnswerMessageRequestUseCase(messaging: messagingRepository),
            deleteConversation: DeleteConversationUseCase(messaging: messagingRepository),
            sendTyping: SendTypingUseCase(channel: channel),
            session: session
        )
        let walletRepository = RemoteWalletRepository(client: client)
        self.walletRepository = walletRepository
        wallet = WalletModel(
            loadBalance: LoadWalletBalanceUseCase(wallet: walletRepository),
            purchases: Self.makePurchaseService(configuration),
            session: session,
            analytics: analytics
        )
        realtime = RealtimeCoordinator(channel: channel, publishing: publishing, activity: activity, messaging: messaging, wallet: wallet)
    }

    // RevenueCat avec une clé (Config/Local.xcconfig) ; sinon achats indisponibles. En Debug, `-fakePurchases`
    // simule des achats sans compte RevenueCat (rien n'est payé ni crédité).
    private static func makePurchaseService(_ configuration: AppConfiguration) -> any PurchaseService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fakePurchases") { return DevelopmentPurchaseService() }
        #endif
        return configuration.revenueCatAPIKey.map { RevenueCatPurchaseService(apiKey: $0) } ?? UnavailablePurchaseService()
    }

    // Connexion, déconnexion, passage au premier plan ou en arrière-plan.
    func activityChanged(signedIn: Bool, active: Bool) {
        realtime.update(signedIn: signedIn, active: active)
        Task { await publishing.update(signedIn: signedIn, active: active) }
        if !signedIn {
            activity.reset()
            messaging.reset()
            wallet.reset()
        }
    }

    // Badge de l'onglet « Boîte de réception » : activité, conversations non lues et demandes reçues.
    var inboxBadgeCount: Int {
        activity.unreadCount + messaging.badgeCount
    }

    func makeConversationViewModel(_ route: ConversationRoute) -> ConversationViewModel {
        ConversationViewModel(
            route: route,
            loadConversation: LoadConversationUseCase(messaging: messagingRepository),
            loadMessages: LoadMessagesUseCase(messaging: messagingRepository),
            sendMessage: SendMessageUseCase(messaging: messagingRepository),
            markRead: MarkConversationReadUseCase(messaging: messagingRepository),
            answerRequest: AnswerMessageRequestUseCase(messaging: messagingRepository),
            deleteConversation: DeleteConversationUseCase(messaging: messagingRepository),
            deleteMessage: DeleteMessageUseCase(messaging: messagingRepository),
            messaging: messaging,
            session: session,
            analytics: analytics
        )
    }

    // Abonnements du compte connecté (« Nouveau message »).
    func makeFollowingList() -> PagedList<FollowEntry> {
        let load = LoadFollowsUseCase(relationships: relationships)
        let username = session.profile?.username
        return PagedList(session: session) { cursor in
            guard let username else { return ([], nil) }
            let page = try await load(.following, username: username, cursor: cursor)
            return (page.entries, page.nextCursor)
        }
    }

    // « Envoyer par message » depuis la feuille de partage d'une vidéo.
    func makeSendVideoViewModel(video: FeedVideo) -> SendVideoViewModel {
        SendVideoViewModel(
            video: video,
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: relationships),
            share: ShareVideoByMessageUseCase(messaging: messagingRepository),
            interactions: videoInteractions,
            session: session
        )
    }

    // Historique des mouvements de jetons (paywall).
    func makeWalletTransactionList() -> PagedList<WalletTransaction> {
        let load = LoadWalletTransactionsUseCase(wallet: walletRepository)
        return PagedList(session: session) { cursor in
            let page = try await load(cursor: cursor)
            return (page.transactions, page.nextCursor)
        }
    }

    // Liste complète d'un groupe du centre d'activité.
    func makeActivityGroupList(_ filter: ActivityFilter) -> PagedList<ActivityNotification> {
        let load = LoadActivityGroupUseCase(activity: activityRepository, actorRelationships: LoadActorRelationshipsUseCase(relationships: relationships))
        return PagedList(session: session) { cursor in
            let page = try await load(filter, cursor: cursor)
            return (page.notifications, page.nextCursor)
        }
    }

    func makePublishDraftViewModel() -> PublishDraftViewModel {
        PublishDraftViewModel(publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: AVFoundationVideoMetadataCleaner()))
    }

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(login: LoginUseCase(auth: auth, profiles: profiles), session: session, analytics: analytics)
    }

    func makeRegisterViewModel() -> RegisterViewModel {
        RegisterViewModel(register: RegisterUseCase(auth: auth, profiles: profiles), session: session, analytics: analytics)
    }

    func makeFeedViewModel() -> FeedViewModel {
        FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: feed),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session,
            analytics: analytics
        )
    }

    // Signalement d'une vidéo, d'un commentaire ou d'un compte (ADR-038).
    func makeReportViewModel(target: ReportTarget) -> ReportViewModel {
        ReportViewModel(target: target, sendReport: SendReportUseCase(reports: reports), session: session, analytics: analytics)
    }

    func makeCommentsViewModel(video: FeedVideo, onCountChange: @escaping (Int) -> Void) -> CommentsViewModel {
        CommentsViewModel(
            video: video,
            loadComments: LoadCommentsUseCase(interactions: interactions),
            addComment: AddCommentUseCase(interactions: interactions),
            deleteComment: DeleteCommentUseCase(interactions: interactions),
            session: session,
            analytics: analytics,
            onCountChange: onCountChange
        )
    }

    func makeVideoDetailViewModel(videoID: String) -> VideoDetailViewModel {
        VideoDetailViewModel(
            videoID: videoID,
            loadVideo: LoadVideoUseCase(feed: feed),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session,
            analytics: analytics
        )
    }

    // `username` nil : son propre profil.
    func makeProfileViewModel(username: String?) -> ProfileViewModel {
        ProfileViewModel(
            username: username,
            getMyProfile: GetMyProfileUseCase(profiles: profiles),
            loadProfile: LoadProfileUseCase(profiles: profiles),
            loadRelationship: LoadRelationshipUseCase(relationships: relationships),
            loadVideoPage: LoadVideoPageUseCase(videos: videoLists),
            setBlocked: SetBlockedUseCase(relationships: relationships),
            interactions: videoInteractions,
            session: session
        )
    }

    func makeEditProfileViewModel() -> EditProfileViewModel {
        EditProfileViewModel(
            updateProfile: UpdateProfileUseCase(profiles: profiles),
            changeAvatar: ChangeAvatarUseCase(profiles: profiles, transport: URLSessionAvatarUploader()),
            removeAvatar: RemoveAvatarUseCase(profiles: profiles),
            session: session
        )
    }

    func makeFollowListViewModel(_ route: FollowListRoute) -> FollowListViewModel {
        FollowListViewModel(
            kind: route.kind,
            username: route.username,
            loadFollows: LoadFollowsUseCase(relationships: relationships),
            interactions: videoInteractions,
            session: session
        )
    }

    func makeAccountSettingsViewModel() -> AccountSettingsViewModel {
        AccountSettingsViewModel(
            deleteAccount: DeleteAccountUseCase(profiles: profiles, auth: auth),
            discardUploads: DiscardUploadsUseCase(store: uploads),
            session: session
        )
    }

    func makeViewHistoryViewModel() -> ViewHistoryViewModel {
        ViewHistoryViewModel(
            loadVideoPage: LoadVideoPageUseCase(videos: videoLists),
            removeFromHistory: RemoveFromHistoryUseCase(videos: videoLists),
            clearHistory: ClearHistoryUseCase(videos: videoLists),
            session: session
        )
    }

    func makeCommentHistoryViewModel() -> CommentHistoryViewModel {
        CommentHistoryViewModel(
            loadComments: LoadCommentHistoryUseCase(interactions: interactions),
            deleteComment: DeleteCommentUseCase(interactions: interactions),
            interactions: videoInteractions,
            session: session
        )
    }

    func makeBlockedAccountsViewModel() -> BlockedAccountsViewModel {
        BlockedAccountsViewModel(
            loadBlockedUsers: LoadBlockedUsersUseCase(relationships: relationships),
            setBlocked: SetBlockedUseCase(relationships: relationships),
            interactions: videoInteractions,
            session: session
        )
    }

    // Lecteur vertical ouvert depuis une grille.
    func makeVideoListViewModel(_ route: VideoPlayerRoute) -> FeedViewModel {
        FeedViewModel(
            loadPage: LoadVideoListUseCase(videos: videoLists, list: route.list),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session,
            analytics: analytics,
            mode: .list(route.page, startIndex: route.startIndex)
        )
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
