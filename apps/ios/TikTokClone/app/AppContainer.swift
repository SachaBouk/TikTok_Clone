import AVFoundation
import Foundation
import TikTokAPI
import UIKit

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
    // Historique des recherches (ADR-049), sur l'appareil.
    let searchHistory: SearchHistoryModel
    // Stories (ADR-051) : rangée de la boîte de réception et anneaux autour des avatars.
    let stories: StoriesModel
    // Lives (ADR-053) : lives en cours des abonnements et des profils ouverts.
    let lives: LiveModel
    // Onboarding du premier lancement (ADR-055).
    let onboarding = OnboardingModel(preferences: UserDefaultsPreferencesStore())
    private let auth: any AuthRepository
    private let profiles: any ProfileRepository
    private let signupRepository: any SignupRepository
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
    private let search: any SearchRepository
    private let gifts: any GiftRepository
    private let storyRepository: RemoteStoryRepository
    private let liveRepository: RemoteLiveRepository
    // Compte connecté ou non au dernier changement d'activité : l'historique des recherches est effacé à chaque
    // changement de session.
    private var lastSignedIn: Bool?

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
        signupRepository = RemoteSignupRepository(client: client)
        feed = RemoteFeedRepository(client: client)
        viewHistory = RemoteViewHistoryRepository(client: client)
        interactions = RemoteInteractionRepository(client: client)
        relationships = RemoteRelationshipRepository(client: client)
        reports = RemoteReportRepository(client: client)
        videoLists = RemoteVideoListRepository(client: client)
        search = RemoteSearchRepository(client: client)
        gifts = RemoteGiftRepository(client: client)
        searchHistory = SearchHistoryModel(store: UserDefaultsPreferencesStore())
        let videos = RemoteVideoPublishingRepository(client: client)
        let storyRepository = RemoteStoryRepository(client: client)
        self.storyRepository = storyRepository
        let uploads = FileUploadStore()
        self.uploads = uploads
        session = SessionStore(
            restoreSession: RestoreSessionUseCase(auth: auth, profiles: profiles),
            logout: LogoutUseCase(auth: auth)
        )
        expiry.session = session
        let analyticsService: any AnalyticsService =
            configuration.analytics.map { PostHogAnalyticsService(configuration: $0) }
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
            uploadVideo: UploadVideoUseCase(videos: videos, stories: storyRepository, transport: URLSessionPartUploader(), store: uploads),
            pendingUploads: PendingUploadsUseCase(store: uploads),
            cancelUpload: CancelUploadUseCase(videos: videos, stories: storyRepository, store: uploads),
            loadPendingVideos: LoadPendingVideosUseCase(videos: videos),
            loadVideo: LoadOwnVideoUseCase(videos: videos),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            loadStory: LoadOwnStoryUseCase(stories: storyRepository),
            deleteStory: DeleteStoryUseCase(stories: storyRepository),
            session: session,
            analytics: analytics
        )
        stories = StoriesModel(
            loadTray: LoadStoryTrayUseCase(stories: storyRepository), loadStories: LoadUserStoriesUseCase(stories: storyRepository),
            session: session)
        publishing.onStoryPublished = { [stories] in Task { await stories.refresh() } }
        let liveRepository = RemoteLiveRepository(client: client)
        self.liveRepository = liveRepository
        lives = LiveModel(
            loadFollowing: LoadFollowingLivesUseCase(lives: liveRepository), loadUserLive: LoadUserLiveUseCase(lives: liveRepository),
            session: session)
        let activityRepository = RemoteActivityRepository(client: client)
        self.activityRepository = activityRepository
        activity = ActivityModel(
            loadGroups: LoadActivityGroupsUseCase(
                activity: activityRepository, actorRelationships: LoadActorRelationshipsUseCase(relationships: relationships)),
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
        realtime = RealtimeCoordinator(
            channel: channel, publishing: publishing, activity: activity, messaging: messaging, wallet: wallet, stories: stories,
            ownProfile: OwnProfileSync(session: session, getMyProfile: GetMyProfileUseCase(profiles: profiles)))
    }

    // RevenueCat avec une clé (Config/Local.xcconfig) ; sinon achats indisponibles. En Debug, `-fakePurchases`
    // simule des achats sans compte RevenueCat (rien n'est payé ni crédité).
    private static func makePurchaseService(_ configuration: AppConfiguration) -> any PurchaseService {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-fakePurchases") { return DevelopmentPurchaseService() }
        #endif
        return configuration.revenueCatAPIKey.map { RevenueCatPurchaseService(apiKey: $0) } ?? UnavailablePurchaseService()
    }

    // Session reprise au lancement : état de départ des changements de session (historique des recherches).
    func sessionRestored(signedIn: Bool) {
        lastSignedIn = signedIn
    }

    // Connexion, déconnexion, passage au premier plan ou en arrière-plan.
    func activityChanged(signedIn: Bool, active: Bool) {
        // Connexion, déconnexion ou suppression du compte (pas au lancement) : historique des recherches effacé.
        // Pendant la reprise de la session, « non connecté » n'est pas un état : le retenir effaçait l'historique à
        // chaque lancement d'un compte connecté (`sessionRestored` pose l'état de départ).
        if session.state != .restoring {
            if let lastSignedIn, lastSignedIn != signedIn { searchHistory.clear() }
            lastSignedIn = signedIn
        }
        realtime.update(signedIn: signedIn, active: active)
        Task { await publishing.update(signedIn: signedIn, active: active) }
        if !signedIn {
            activity.reset()
            messaging.reset()
            wallet.reset()
            stories.reset()
            lives.reset()
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

    // « Envoyer à » d'un live (ADR-053).
    func makeSendLiveViewModel(live: LiveStream) -> SendVideoViewModel {
        SendVideoViewModel(
            item: .live(live),
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: relationships),
            share: ShareVideoByMessageUseCase(messaging: messagingRepository),
            shareLive: ShareLiveByMessageUseCase(messaging: messagingRepository),
            interactions: videoInteractions,
            session: session
        )
    }

    // Écran d'un live (ADR-053) : sa salle LiveKit (une par ouverture) et son modèle.
    func makeLiveRoom(_ route: AppRouter.LiveRoute) -> LiveRoomSetup {
        let room = LiveKitRoom()
        let model = LiveRoomModel(
            mode: route.mode,
            room: room,
            startLive: StartLiveUseCase(lives: liveRepository),
            joinLive: JoinLiveUseCase(lives: liveRepository),
            loadLive: LoadLiveUseCase(lives: liveRepository),
            endLive: EndLiveUseCase(lives: liveRepository),
            sendMessage: SendLiveMessageUseCase(lives: liveRepository),
            deleteMessage: DeleteLiveMessageUseCase(lives: liveRepository),
            sendHearts: SendLiveHeartsUseCase(lives: liveRepository),
            lives: lives,
            session: session,
            analytics: analytics,
            hiddenUserIDs: { [videoInteractions] in videoInteractions.blockedUserIDs }
        )
        return LiveRoomSetup(model: model, room: room)
    }

    // Historique des mouvements de jetons (paywall).
    func makeWalletTransactionList() -> PagedList<WalletTransaction> {
        let load = LoadWalletTransactionsUseCase(wallet: walletRepository)
        return PagedList(session: session) { cursor in
            let page = try await load(cursor: cursor)
            return (page.transactions, page.nextCursor)
        }
    }

    // Cadeaux reçus (ADR-050).
    func makeReceivedGiftList() -> PagedList<ReceivedGift> {
        let load = LoadReceivedGiftsUseCase(wallet: walletRepository)
        return PagedList(session: session) { cursor in
            let page = try await load(cursor: cursor)
            return (page.gifts, page.nextCursor)
        }
    }

    // Feuille de cadeaux sur une vidéo (ADR-050).
    func makeGiftSheetViewModel(video: FeedVideo) -> GiftSheetViewModel {
        makeGiftSheetViewModel(target: .video(id: video.id, author: video.author))
    }

    // Feuille de cadeaux d'une vidéo ou d'un live (ADR-053).
    func makeGiftSheetViewModel(target: GiftTarget) -> GiftSheetViewModel {
        GiftSheetViewModel(
            target: target,
            loadCatalog: LoadGiftCatalogUseCase(gifts: gifts),
            sendGift: SendGiftUseCase(gifts: gifts),
            wallet: wallet,
            session: session,
            analytics: analytics
        )
    }

    // Liste complète d'un groupe du centre d'activité.
    func makeActivityGroupList(_ filter: ActivityFilter) -> PagedList<ActivityNotification> {
        let load = LoadActivityGroupUseCase(
            activity: activityRepository, actorRelationships: LoadActorRelationshipsUseCase(relationships: relationships))
        return PagedList(session: session) { cursor in
            let page = try await load(filter, cursor: cursor)
            return (page.notifications, page.nextCursor)
        }
    }

    func makePublishDraftViewModel() -> PublishDraftViewModel {
        PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: AVFoundationVideoMetadataCleaner()),
            preparePhoto: PrepareStoryPhotoUseCase(renderer: UIKitStoryPhotoRenderer()),
            searchHashtags: SearchHashtagsUseCase(search: search))
    }

    // Caméra (ADR-052) : son modèle et la session de capture pour l'aperçu. Une caméra par ouverture de l'écran.
    func makeCamera(kind: PublicationKind) -> CameraSetup {
        let camera = AVFoundationVideoCamera()
        return CameraSetup(model: CameraViewModel(kind: kind, camera: camera), session: camera.session)
    }

    // Éditeur (ADR-052) : export sur l'iPhone, miniatures de la frise.
    func makeVideoEditor(_ request: EditorRequest) -> VideoEditorViewModel {
        VideoEditorViewModel(
            request: request, exportVideo: ExportEditedVideoUseCase(editor: AVFoundationVideoEditor()),
            makeThumbnails: { plan, count in await EditThumbnails.images(for: plan, count: count) })
    }

    // Visionneuse de stories (ADR-051).
    func makeStoryViewerModel(_ route: AppRouter.StoriesRoute) -> StoryViewerModel {
        StoryViewerModel(
            authors: route.authors,
            startAuthor: route.startAuthor,
            source: route.source,
            loadStories: LoadUserStoriesUseCase(stories: storyRepository),
            recordView: RecordStoryViewUseCase(stories: storyRepository),
            setLiked: SetStoryLikedUseCase(stories: storyRepository),
            deleteStory: DeleteStoryUseCase(stories: storyRepository),
            reply: ReplyToStoryUseCase(messaging: messagingRepository),
            model: stories,
            session: session,
            analytics: analytics
        )
    }

    // Personnes qui ont vu sa story.
    func makeStoryViewersList(storyID: String) -> PagedList<StoryViewer> {
        let load = LoadStoryViewersUseCase(stories: storyRepository)
        return PagedList(session: session) { cursor in
            let page = try await load(storyID: storyID, cursor: cursor)
            return (page.viewers, page.nextCursor)
        }
    }

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(login: LoginUseCase(auth: auth, profiles: profiles), session: session, analytics: analytics)
    }

    func makeSignupFlowModel() -> SignupFlowModel {
        SignupFlowModel(
            register: RegisterUseCase(auth: auth, profiles: profiles),
            checkUsername: CheckUsernameUseCase(signup: signupRepository),
            loadCatalog: LoadInterestCatalogUseCase(signup: signupRepository),
            saveInterests: SaveInterestsUseCase(signup: signupRepository),
            session: session,
            analytics: analytics
        )
    }

    func makeInterestsSettingsViewModel() -> InterestsSettingsViewModel {
        InterestsSettingsViewModel(
            loadCatalog: LoadInterestCatalogUseCase(signup: signupRepository),
            loadMine: LoadMyInterestsUseCase(signup: signupRepository),
            save: SaveInterestsUseCase(signup: signupRepository),
            session: session
        )
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

    // Recherche de comptes et hashtags (ADR-049).
    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(
            searchAccounts: SearchAccountsUseCase(search: search),
            searchHashtags: SearchHashtagsUseCase(search: search),
            loadTrending: LoadTrendingHashtagsUseCase(search: search),
            history: searchHistory,
            interactions: videoInteractions,
            session: session
        )
    }

    func makeHashtagViewModel(name: String) -> HashtagViewModel {
        HashtagViewModel(
            name: name,
            loadHashtag: LoadHashtagUseCase(search: search),
            loadVideos: LoadVideoListUseCase(videos: videoLists, list: .hashtag(name: name)),
            interactions: videoInteractions,
            session: session
        )
    }

    // Suggestions de hashtags de la publication (ADR-049).
    var searchHashtags: SearchHashtagsUseCase { SearchHashtagsUseCase(search: search) }

    // Feed des abonnements (ADR-048) : du plus récent au plus ancien, il s'arrête à sa fin.
    func makeFollowingFeedViewModel() -> FeedViewModel {
        FeedViewModel(
            loadPage: LoadFollowingFeedPageUseCase(feed: feed),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session,
            analytics: analytics,
            mode: .followingFeed
        )
    }

    // Feed des amis (ADR-054) : vidéos des abonnés mutuels, du plus récent au plus ancien, il s'arrête à sa fin.
    func makeFriendsFeedViewModel() -> FeedViewModel {
        FeedViewModel(
            loadPage: LoadFriendsFeedPageUseCase(feed: feed),
            recordView: RecordViewUseCase(history: viewHistory),
            playback: playerPool,
            session: session,
            analytics: analytics,
            mode: .friendsFeed
        )
    }

    // Signalement d'une vidéo, d'un commentaire ou d'un compte (ADR-038).
    // `author` : auteur d'une vidéo ou d'un commentaire, que l'écran de remerciement propose de bloquer.
    func makeReportViewModel(target: ReportTarget, author: UserSummary? = nil) -> ReportViewModel {
        ReportViewModel(
            target: target, sendReport: SendReportUseCase(reports: reports), session: session, analytics: analytics, author: author,
            setBlocked: SetBlockedUseCase(relationships: relationships), interactions: videoInteractions)
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
            session: session,
            // Story « nouvelle photo de profil » (ADR-056) : dessinée, préparée comme une story photo, puis mise en file.
            publishStory: { [session, publishing] avatar in
                guard let username = session.profile?.username, let image = UIImage(data: avatar),
                    let story = ProfilePhotoStory.render(avatar: image, username: username, date: .now)
                else { return "Impossible de préparer la story." }
                do {
                    let file = try await PrepareStoryPhotoUseCase(renderer: UIKitStoryPhotoRenderer())(story)
                    return publishing.publish(
                        file: file, description: "", preview: UIImage(data: story), kind: .story,
                        details: PublicationDetails(source: .profilePhoto))
                } catch {
                    return AppError.from(error).message
                }
            }
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
