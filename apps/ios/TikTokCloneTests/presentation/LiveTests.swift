import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@Suite("Live : règles (ADR-053)")
struct LiveRulesTests {
    @Test("titre et message nettoyés ; message vide ou de plus de 150 caractères refusé")
    func sanitizing() {
        #expect(LiveRules.sanitizedTitle("  Mon live \n") == "Mon live")
        #expect(LiveRules.sanitizedTitle("   ") == nil)
        #expect(LiveRules.sanitizedMessage("  salut  ") == "salut")
        #expect(LiveRules.sanitizedMessage(" \n ") == nil)
        #expect(LiveRules.sanitizedMessage(String(repeating: "a", count: 150)) != nil)
        #expect(LiveRules.sanitizedMessage(String(repeating: "a", count: 151)) == nil)
    }

    @Test("chat : sans doublon, retraits appliqués, 100 messages gardés, comptes bloqués masqués")
    func chat() {
        var chat = LiveChat([.sample("m1"), .sample("m1"), .sample("m2", by: .alice)])
        #expect(chat.messages.map(\.id) == ["m1", "m2"])
        chat.append(.sample("m2", by: .alice))
        chat.remove(id: "m1")
        #expect(chat.messages.map(\.id) == ["m2"])
        #expect(chat.hiding([UserSummary.alice.id]).isEmpty)
        for index in 0..<120 { chat.append(.sample("x\(index)")) }
        #expect(chat.messages.count == LiveRules.maxChatMessages)
        #expect(chat.messages.last?.id == "x119")
    }

    @Test("cœurs par lots de 30 au plus, le reste au lot suivant")
    func heartBatches() {
        var batch = HeartBatch()
        #expect(batch.take() == nil)
        for _ in 0..<45 { batch.tap() }
        #expect(batch.take() == 30)
        #expect(batch.take() == 15)
        #expect(batch.take() == nil)
    }

    @Test("lien d'app : tiktokclone://lives/<id>, identifiant en minuscules ; autres liens refusés")
    func link() throws {
        let id = "0192F3A0-0000-7000-8000-000000000042"
        let url = LiveLink.url(for: id.lowercased())
        #expect(url.absoluteString == "tiktokclone://lives/0192f3a0-0000-7000-8000-000000000042")
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://lives/\(id)"))) == id.lowercased())
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://lives/pas-un-uuid"))) == nil)
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://videos/\(id)"))) == nil)
        #expect(VideoLink.videoID(from: url) == nil)
    }

    @Test("durée affichée des chiffres du live")
    func duration() {
        let stats = LiveStats(durationSeconds: 125, peakViewers: 3, viewersCount: 5, heartsCount: 10, giftsCount: 1, giftsAmount: 50)
        #expect(stats.durationLabel == "2:05")
    }
}

@MainActor
@Suite("Live : écran, rangée, partage (ADR-053)")
struct LiveRoomTests {
    let repository = FakeLiveRepository()
    let analyticsService = FakeAnalyticsService()

    func makeSession(signedIn: Bool = true) async -> SessionStore {
        let session = TikTokCloneTests.makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        return session
    }

    func makeLives(_ session: SessionStore) -> LiveModel {
        LiveModel(loadFollowing: LoadFollowingLivesUseCase(lives: repository), loadUserLive: LoadUserLiveUseCase(lives: repository), session: session)
    }

    func makeModel(_ mode: LiveRoomModel.Mode, session: SessionStore, room: FakeLiveRoom, lives: LiveModel? = nil, hidden: Set<String> = [])
        -> LiveRoomModel
    {
        LiveRoomModel(
            mode: mode, room: room, startLive: StartLiveUseCase(lives: repository), joinLive: JoinLiveUseCase(lives: repository),
            loadLive: LoadLiveUseCase(lives: repository), endLive: EndLiveUseCase(lives: repository),
            sendMessage: SendLiveMessageUseCase(lives: repository), deleteMessage: DeleteLiveMessageUseCase(lives: repository),
            sendHearts: SendLiveHeartsUseCase(lives: repository), lives: lives ?? makeLives(session), session: session,
            analytics: makeAnalytics(analyticsService), hiddenUserIDs: { hidden }, sleep: { _ in })
    }

    @Test("spectateur : rejoint, regarde sans publier, derniers messages, spectateurs sans l'auteur, mesure d'audience")
    func join() async {
        repository.state.withLock { $0.connection = .sample(messages: [.sample("m1")]) }
        let room = FakeLiveRoom()
        let model = makeModel(.viewer(liveID: "live-1", source: .tray), session: await makeSession(), room: room)
        await model.start()
        #expect(model.phase == .live)
        #expect(room.connected.map(\.publish) == [false])
        #expect(model.messages.map(\.id) == ["m1"])
        #expect(!model.isHost)
        model.apply(.participants(4))
        model.apply(.videoAvailable(true))
        #expect(model.viewersCount == 3)
        #expect(model.hasVideo)
        #expect(analyticsService.events.last?.name == "live_viewed")
        #expect(analyticsService.events.last?.properties["source"] == .string("tray"))
    }

    @Test("auteur : lance avec le titre, publie ; sans caméra, le live est arrêté aussitôt")
    func host() async {
        repository.state.withLock { $0.connection = .sample(.sample(host: .alice), role: .host) }
        let room = FakeLiveRoom()
        let model = makeModel(.host(title: "  Coucou "), session: await makeSession(), room: room)
        await model.start()
        #expect(model.phase == .live)
        #expect(model.isHost)
        #expect(room.connected.map(\.publish) == [true])
        #expect(repository.state.withLock { $0.titles } == ["Coucou"])
        await model.switchCamera()
        #expect(room.cameraSwitches == 1)

        let noCamera = FakeLiveRoom()
        noCamera.connectError = .cameraUnavailable
        let failed = makeModel(.host(title: ""), session: await makeSession(), room: noCamera)
        await failed.start()
        guard case .failed(let message) = failed.phase else {
            Issue.record("échec attendu")
            return
        }
        #expect(message.contains("Caméra indisponible"))
        #expect(repository.ended == ["live-1"])
    }

    @Test("fin par l'auteur : chiffres du live, salle quittée")
    func end() async {
        let stats = LiveStats(durationSeconds: 60, peakViewers: 2, viewersCount: 3, heartsCount: 7, giftsCount: 1, giftsAmount: 5)
        repository.state.withLock {
            $0.connection = .sample(.sample(host: .alice), role: .host)
            $0.lives["live-1"] = .sample(host: .alice, status: .ended, endReason: .host, stats: stats)
        }
        let room = FakeLiveRoom()
        let model = makeModel(.host(title: ""), session: await makeSession(), room: room)
        await model.start()
        await model.end()
        #expect(model.phase == .ended(.sample(host: .alice, status: .ended, endReason: .host, stats: stats), reason: .host))
        #expect(room.disconnects == 1)
        #expect(analyticsService.events.last?.name == "live_ended")
    }

    @Test("chat : message envoyé (sans doublon avec l'écho de la salle), retiré ; comptes bloqués masqués ; invité : pas de saisie")
    func chat() async {
        repository.state.withLock { $0.connection = .sample() }
        let room = FakeLiveRoom()
        let lives = makeLives(await makeSession())
        let model = makeModel(.viewer(liveID: "live-1", source: .link), session: await makeSession(), room: room, lives: lives, hidden: ["carol-id"])
        await model.start()
        model.draft = "  Bravo  "
        #expect(model.canSend)
        await model.send()
        #expect(repository.state.withLock { $0.messages } == ["Bravo"])
        #expect(model.draft.isEmpty)
        model.apply(.event(.chatMessage(.sample("m1", by: .alice, content: "Bravo"))))
        model.apply(.event(.chatMessage(.sample("m2", by: UserSummary(id: "carol-id", username: "carol", displayName: "Carol", avatarURL: nil)))))
        #expect(model.messages.map(\.id) == ["m1"])
        let own = model.messages[0]
        #expect(model.canDelete(own))
        await model.delete(own)
        #expect(model.messages.isEmpty)
        #expect(repository.state.withLock { $0.deleted } == ["m1"])
        model.apply(.event(.chatMessage(.sample("m3"))))
        model.apply(.event(.chatMessageDeleted(id: "m3")))
        #expect(model.messages.isEmpty)

        let guest = makeModel(.viewer(liveID: "live-1", source: .link), session: await makeSession(signedIn: false), room: FakeLiveRoom())
        await guest.start()
        guest.draft = "Salut"
        #expect(!guest.canChat)
        #expect(!guest.canSend)
    }

    @Test("message refusé (429) : erreur affichée, brouillon gardé")
    func messageLimit() async {
        repository.state.withLock {
            $0.connection = .sample()
            $0.messageError = .tooManyActions(.liveMessages, retryAfter: 30)
        }
        let model = makeModel(.viewer(liveID: "live-1", source: .link), session: await makeSession(), room: FakeLiveRoom())
        await model.start()
        model.draft = "Salut"
        await model.send()
        #expect(model.draft == "Salut")
        #expect(model.errorMessage == AppError.tooManyActions(.liveMessages, retryAfter: 30).message)
    }

    @Test("cœurs : un cœur monte à chaque toucher, envoyés par lot ; total de la salle ; invité : connexion")
    func hearts() async {
        repository.state.withLock { $0.connection = .sample() }
        let model = makeModel(.viewer(liveID: "live-1", source: .tray), session: await makeSession(), room: FakeLiveRoom())
        await model.start()
        for _ in 0..<3 { model.tapHeart() }
        #expect(model.floatingHearts.count == 3)
        await model.waitForHearts()
        #expect(repository.hearts == [3])
        #expect(model.heartsTotal == 3)
        model.apply(.event(.hearts(count: 40, total: 50)))
        #expect(model.heartsTotal == 50)
        #expect(model.floatingHearts.count == 8)

        let guestSession = await makeSession(signedIn: false)
        let guest = makeModel(.viewer(liveID: "live-1", source: .tray), session: guestSession, room: FakeLiveRoom())
        await guest.start()
        guest.tapHeart()
        #expect(guestSession.isPresentingSignIn)
        #expect(guest.floatingHearts.isEmpty)
    }

    @Test("cadeau reçu dans la salle : affiché quelques secondes")
    func gifts() async {
        repository.state.withLock { $0.connection = .sample() }
        let model = makeModel(.viewer(liveID: "live-1", source: .tray), session: await makeSession(), room: FakeLiveRoom())
        await model.start()
        model.apply(.event(.gift(sender: .alice, gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, giftsCount: 1, giftsAmount: 1)))
        #expect(model.gifts.map(\.gift.code) == ["rose"])
        // Le délai d'affichage est immédiat dans les tests.
        #expect(await eventually { model.gifts.isEmpty })
    }

    @Test("fin annoncée par la salle : écran de fin, live retiré de la rangée ; salle perdue : le live est relu")
    func endedByRoom() async {
        let session = await makeSession()
        let lives = makeLives(session)
        repository.state.withLock {
            $0.connection = .sample()
            $0.following = [.sample()]
        }
        await lives.refresh()
        #expect(lives.followingLives.map(\.id) == ["live-1"])
        let room = FakeLiveRoom()
        let model = makeModel(.viewer(liveID: "live-1", source: .tray), session: session, room: room, lives: lives)
        await model.start()
        model.apply(.event(.ended(.moderation)))
        #expect(await eventually { model.phase == .ended(.sample(), reason: .moderation) })
        #expect(lives.followingLives.isEmpty)
        #expect(room.disconnects == 1)

        repository.state.withLock { $0.lives["live-1"] = .sample(status: .ended, endReason: .disconnected) }
        let lost = makeModel(.viewer(liveID: "live-1", source: .tray), session: session, room: FakeLiveRoom())
        await lost.start()
        lost.apply(.disconnected)
        #expect(await eventually { lost.phase == .ended(.sample(), reason: .disconnected) })

        repository.state.withLock { $0.lives["live-1"] = .sample() }
        let unstable = makeModel(.viewer(liveID: "live-1", source: .tray), session: session, room: FakeLiveRoom())
        await unstable.start()
        unstable.apply(.disconnected)
        #expect(await eventually { unstable.phase == .failed("Connexion au live perdue.") })
    }

    @Test("live terminé avant l'ouverture : écran de fin ; live introuvable : indisponible")
    func joinErrors() async {
        repository.state.withLock {
            $0.joinError = .rejected("Ce live est terminé.")
            $0.lives["live-1"] = .sample(status: .ended, endReason: .host)
        }
        let session = await makeSession()
        let ended = makeModel(.viewer(liveID: "live-1", source: .message), session: session, room: FakeLiveRoom())
        await ended.start()
        #expect(ended.phase == .ended(.sample(status: .ended, endReason: .host), reason: nil))

        repository.state.withLock { $0.joinError = .notFound }
        let missing = makeModel(.viewer(liveID: "live-2", source: .message), session: session, room: FakeLiveRoom())
        await missing.start()
        #expect(missing.phase == .failed("Ce live n’est plus disponible."))
    }

    @Test("rangée et profils : lives des abonnements, live d'un profil, oubliés une fois terminés et à la déconnexion")
    func liveModel() async {
        let session = await makeSession()
        let lives = makeLives(session)
        repository.state.withLock {
            $0.following = [.sample("l1"), .sample("l2", host: .alice)]
            $0.userLives["carol"] = .sample("l3", host: UserSummary(id: "carol-id", username: "carol", displayName: "Carol", avatarURL: nil))
        }
        await lives.refresh()
        #expect(lives.live(of: UserSummary.bob.id)?.id == "l1")
        await lives.load(for: UserSummary(id: "carol-id", username: "carol", displayName: "Carol", avatarURL: nil))
        #expect(lives.live(of: "carol-id")?.id == "l3")
        lives.ended("l1")
        #expect(lives.followingLives.map(\.id) == ["l2"])
        #expect(lives.live(of: UserSummary.bob.id) == nil)
        await lives.refresh()
        #expect(lives.followingLives.map(\.id) == ["l2"])
        lives.reset()
        #expect(lives.followingLives.isEmpty)
        #expect(lives.live(of: "carol-id") == nil)
    }

    @Test("lien d'app d'un live : le live s'ouvre ; partage par message : un live envoyé")
    func linkAndShare() async throws {
        let router = AppRouter()
        #expect(router.open(try #require(URL(string: "tiktokclone://lives/0192f3a0-0000-7000-8000-000000000042"))))
        #expect(router.presentedLive?.mode == .viewer(liveID: "0192f3a0-0000-7000-8000-000000000042", source: .link))
        #expect(router.coversTabs)

        let session = await makeSession()
        let messagingRepository = FakeMessagingRepository()
        let messaging = MessagingModel(
            loadConversations: LoadConversationsUseCase(messaging: messagingRepository),
            loadRequests: LoadMessageRequestsUseCase(messaging: messagingRepository),
            loadConversation: LoadConversationUseCase(messaging: messagingRepository),
            countUnread: CountUnreadMessagesUseCase(messaging: messagingRepository),
            answerRequest: AnswerMessageRequestUseCase(messaging: messagingRepository),
            deleteConversation: DeleteConversationUseCase(messaging: messagingRepository),
            sendTyping: SendTypingUseCase(channel: FakeRealtimeChannel()),
            session: session
        )
        let interactionRepository = FakeInteractionRepository()
        let viewModel = SendVideoViewModel(
            item: .live(.sample()),
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: FakeRelationshipRepository()),
            share: ShareVideoByMessageUseCase(messaging: messagingRepository),
            shareLive: ShareLiveByMessageUseCase(messaging: messagingRepository),
            interactions: VideoInteractionsModel(
                setReaction: SetReactionUseCase(interactions: interactionRepository),
                setFollow: SetFollowUseCase(interactions: interactionRepository),
                recordShare: ShareVideoUseCase(interactions: interactionRepository),
                deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
                session: session,
                analytics: makeAnalytics()
            ),
            session: session
        )
        await viewModel.send(to: .init(user: .bob))
        #expect(viewModel.deliveries[UserSummary.bob.id] == .sent)
        // Un live, pas de vidéo.
        #expect(messagingRepository.sentVideoIDs == [nil])
    }

    @Test("cadeau sur un live : envoyé au live, mesure d'audience avec le live")
    func liveGift() async {
        let gifts = FakeGiftRepository()
        let walletRepository = FakeWalletRepository()
        let session = TikTokCloneTests.makeSession()
        session.signedIn(.alice)
        walletRepository.setBalance(10)
        let analytics = makeAnalytics(analyticsService)
        let wallet = WalletModel(
            loadBalance: LoadWalletBalanceUseCase(wallet: walletRepository), purchases: FakePurchaseService(), session: session, analytics: analytics)
        let viewModel = GiftSheetViewModel(
            target: .live(id: "live-1", host: .bob), loadCatalog: LoadGiftCatalogUseCase(gifts: gifts), sendGift: SendGiftUseCase(gifts: gifts),
            wallet: wallet, session: session, analytics: analytics)
        await viewModel.load()
        gifts.enqueue(.success(SentGift(id: "g1", gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, balance: 9)))
        _ = await viewModel.send()
        #expect(gifts.sent.map(\.video) == ["live:live-1"])
        #expect(wallet.balance == 9)
        #expect(analyticsService.events.last?.properties["live_id"] == .string("live-1"))
    }
}

@Suite("Live : API (ADR-053)")
struct LiveDataTests {
    static let live = """
        {"id":"0192f3a0-0000-7000-8000-000000000042","userId":"0192f3a0-0000-7000-8000-000000000002",\
        "title":"Mon live","status":"live","startedAt":"2026-10-09T10:00:00.000Z","endedAt":null,\
        "host":{"id":"0192f3a0-0000-7000-8000-000000000002","username":"bob","displayName":"Bob","avatarUrl":null}}
        """

    @Test("rejoindre : mapping de la connexion ; 404, 409 terminé")
    func join() async throws {
        let repository = RemoteLiveRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    json(.ok, #"{"live":\#(Self.live),"role":"viewer","url":"ws://localhost:7880","token":"t","recentMessages":[]}"#)
                }))
        let connection = try await repository.join(liveID: "0192f3a0-0000-7000-8000-000000000042")
        #expect(connection.role == .viewer)
        #expect(connection.live.title == "Mon live")
        #expect(connection.live.isLive)
        #expect(connection.url.absoluteString == "ws://localhost:7880")

        let missing = RemoteLiveRepository(client: makeClient(transport: MockTransport { _, _ in json(.notFound, errorJSON(404, "x")) }))
        await #expect(throws: AppError.notFound) { try await missing.join(liveID: "x") }
        let ended = RemoteLiveRepository(
            client: makeClient(transport: MockTransport { _, _ in json(.conflict, errorJSON(409, "Ce live est terminé.")) }))
        await #expect(throws: AppError.rejected("Ce live est terminé.")) { try await ended.join(liveID: "x") }
    }

    @Test("lancer : 429 avec délai")
    func startLimit() async {
        let repository = RemoteLiveRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    var (response, body) = json(.tooManyRequests, errorJSON(429, "x"))
                    response.headerFields[.retryAfter] = "3600"
                    return (response, body)
                }))
        await #expect(throws: AppError.tooManyActions(.lives, retryAfter: 3600)) { try await repository.start(title: nil) }
    }

    @Test("événements de la salle décodés avec le contrat ; inconnu ou illisible ignoré")
    func roomEvents() {
        let gift = """
            {"event":"gift","data":{"sender":{"id":"u1","username":"alice","displayName":"Alice","avatarUrl":null},\
            "gift":{"code":"rose","name":"Rose","emoji":"🌹"},"amount":1,"giftsCount":2,"giftsAmount":6}}
            """
        #expect(
            LiveRoomEvent(data: Data(gift.utf8))
                == .gift(
                    sender: UserSummary(id: "u1", username: "alice", displayName: "Alice", avatarURL: nil),
                    gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, giftsCount: 2, giftsAmount: 6))
        #expect(LiveRoomEvent(data: Data(#"{"event":"hearts","data":{"count":3,"total":10}}"#.utf8)) == .hearts(count: 3, total: 10))
        #expect(LiveRoomEvent(data: Data(#"{"event":"liveEnded","data":{"reason":"timeLimit"}}"#.utf8)) == .ended(.timeLimit))
        #expect(LiveRoomEvent(data: Data(#"{"event":"chatMessageDeleted","data":{"messageId":"m1"}}"#.utf8)) == .chatMessageDeleted(id: "m1"))
        let message = """
            {"event":"chatMessage","data":{"id":"m1","liveId":"l1","user":{"id":"u1","username":"alice","displayName":"Alice","avatarUrl":null},\
            "content":"Salut","createdAt":"2026-10-09T10:00:00.000Z"}}
            """
        guard case .chatMessage(let chat) = LiveRoomEvent(data: Data(message.utf8)) else {
            Issue.record("message attendu")
            return
        }
        #expect(chat.content == "Salut")
        #expect(LiveRoomEvent(data: Data(#"{"event":"inconnu","data":{}}"#.utf8)) == nil)
        #expect(LiveRoomEvent(data: Data("pas du json".utf8)) == nil)
    }
}
