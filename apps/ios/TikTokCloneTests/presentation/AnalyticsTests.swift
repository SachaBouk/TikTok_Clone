import Foundation
import Testing

@testable import TikTokClone

@Suite("Mesure d'audience : règles du visionnage")
struct WatchRulesTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("chronomètre : seul le temps de lecture compte, pauses exclues ; remis à zéro à la fin")
    func timer() throws {
        var timer = WatchTimer()
        timer.start("v1", at: start)
        timer.pause(at: start.addingTimeInterval(2))
        timer.resume(at: start.addingTimeInterval(10))
        let finished = timer.finish(at: start.addingTimeInterval(11.5))
        let result = try #require(finished)
        #expect(result.videoID == "v1")
        #expect(result.watched == .milliseconds(3500))
        let again = timer.finish(at: start.addingTimeInterval(20))
        #expect(again == nil)

        // Aucun temps de lecture : rien à envoyer.
        timer.start("v2", at: start)
        let empty = timer.finish(at: start)
        #expect(empty == nil)
    }

    @Test("visionnage : taux de complétion arrondi, vue en entier à 90 %, boucles")
    func completion() {
        func watch(_ watched: Duration, of duration: Duration?) -> VideoWatch {
            VideoWatch(
                videoID: "v1", authorID: "bob-id", source: .feed, watched: watched, duration: duration, exitPosition: .seconds(2), exit: .swipe)
        }
        #expect(watch(.seconds(3), of: .seconds(10)).completion == 0.3)
        #expect(!watch(.seconds(3), of: .seconds(10)).completed)
        #expect(watch(.seconds(9), of: .seconds(10)).completed)
        #expect(watch(.seconds(25), of: .seconds(10)).loops == 2)
        #expect(watch(.seconds(3), of: nil).completion == nil)

        let event = AnalyticsEvent.videoWatched(watch(.milliseconds(4500), of: .seconds(10)))
        #expect(event.name == "video_watched")
        #expect(event.properties["watch_ms"] == .int(4500))
        #expect(event.properties["duration_ms"] == .int(10_000))
        #expect(event.properties["completion"] == .double(0.45))
        #expect(event.properties["exit_position_ms"] == .int(2000))
        #expect(event.properties["exit"] == .string("swipe"))
        #expect(event.properties["source"] == .string("feed"))
        // Durée inconnue : pas de complétion.
        #expect(AnalyticsEvent.videoWatched(watch(.seconds(1), of: nil)).properties["completion"] == nil)
    }

    @Test("invité : vidéos différentes comptées jusqu'au seuil, signalé une seule fois")
    func guestCounter() {
        var counter = GuestWatchCounter()
        let reached = ["a", "a", "b", "c", "d", "e", "f"].map { counter.record($0) }
        #expect(reached == [false, false, false, false, false, true, false])
    }
}

@MainActor
@Suite("Mesure d'audience : consentement, identification, expérience")
struct AnalyticsModelTests {
    let service = FakeAnalyticsService()
    let preferences = InMemoryPreferencesStore()

    @Test("sans réponse : rien n'est envoyé, la question est posée ; accepter démarre et identifie le compte connecté")
    func consent() {
        let model = AnalyticsModel(service: service, preferences: preferences)
        model.sessionChanged(userID: "alice-id")
        model.track(.loginCompleted)
        #expect(!service.isStarted)
        #expect(service.events.isEmpty)
        model.askConsentIfNeeded()
        #expect(model.isAskingConsent)

        model.setConsent(true)
        #expect(!model.isAskingConsent)
        #expect(preferences.analyticsConsent == true)
        #expect(service.isStarted)
        #expect(service.identified == ["alice-id"])
        model.track(.loginCompleted)
        #expect(service.eventNames == ["login_completed"])

        // Réponse enregistrée : la question n'est plus posée au lancement suivant.
        let relaunched = AnalyticsModel(service: FakeAnalyticsService(), preferences: preferences)
        relaunched.askConsentIfNeeded()
        #expect(!relaunched.isAskingConsent)
    }

    @Test("refus ou retrait : service arrêté, plus aucun événement ni flag")
    func decline() {
        let model = makeAnalytics(service, preferences: preferences)
        model.setConsent(true)
        model.setConsent(false)
        #expect(!service.isStarted)
        #expect(preferences.analyticsConsent == false)
        model.track(.signupStarted)
        #expect(model.variant(of: GuestPromptExperiment.flag) == nil)
        #expect(service.events.isEmpty)
        #expect(service.flagReads.isEmpty)
    }

    @Test("connexion : identifiant seul ; déconnexion : nouvel identifiant anonyme")
    func identification() {
        let model = makeAnalytics(service)
        model.sessionChanged(userID: nil)
        #expect(service.resetCount == 0)
        model.sessionChanged(userID: "alice-id")
        model.sessionChanged(userID: "alice-id")
        #expect(service.identified == ["alice-id"])
        model.sessionChanged(userID: nil)
        #expect(service.resetCount == 1)
    }

    @Test("expérience invité : variante → invitation une seule fois ; témoin → rien ; flags pas chargés → réessayé")
    func guestExperiment() {
        preferences.setAnalyticsConsent(true)
        let model = makeAnalytics(service, preferences: preferences)
        #expect(!model.shouldPromptGuest())
        #expect(service.flagReads == [GuestPromptExperiment.flag])
        #expect(!preferences.guestPromptDecided)

        service.flags[GuestPromptExperiment.flag] = GuestPromptExperiment.promptVariant
        #expect(model.shouldPromptGuest())
        #expect(service.eventNames == ["guest_prompt_shown"])
        #expect(!model.shouldPromptGuest())

        let control = FakeAnalyticsService()
        control.flags[GuestPromptExperiment.flag] = "control"
        let controlModel = makeAnalytics(control)
        #expect(!controlModel.shouldPromptGuest())
        #expect(control.flagReads == [GuestPromptExperiment.flag])
        #expect(control.events.isEmpty)
    }

    @Test("sans consentement : pas d'expérience (groupe témoin), le flag n'est pas lu")
    func noConsentNoExperiment() {
        service.flags[GuestPromptExperiment.flag] = GuestPromptExperiment.promptVariant
        let model = AnalyticsModel(service: service, preferences: InMemoryPreferencesStore(consent: false))
        #expect(!model.shouldPromptGuest())
        #expect(service.flagReads.isEmpty)
    }
}

@MainActor
@Suite("Mesure d'audience : écrans")
struct AnalyticsInstrumentationTests {
    let service = FakeAnalyticsService()
    let playback = FakePlayback()
    let clock = TestClock()

    func makeFeed(_ ids: [String], signedIn: Bool) async -> (FeedViewModel, SessionStore) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        let viewModel = FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: FakeFeedRepository([.success(page(ids, next: nil))])),
            recordView: RecordViewUseCase(history: FakeViewHistoryRepository()),
            playback: playback,
            session: session,
            analytics: makeAnalytics(service),
            viewDelay: .milliseconds(10),
            now: { [clock] in clock.now }
        )
        return (viewModel, session)
    }

    @Test("feed : temps de lecture (pause exclue), durée et moment du swipe ; sortie de l'écran")
    func videoWatched() async throws {
        let (viewModel, _) = await makeFeed(["a", "b"], signedIn: true)
        await viewModel.start()
        playback.progress["a"] = PlaybackProgress(position: .milliseconds(2500), duration: .seconds(10))
        clock.advance(by: 2)
        viewModel.togglePause()
        clock.advance(by: 30)
        viewModel.togglePause()
        clock.advance(by: 1.5)
        viewModel.show(viewModel.entries[1].id)

        let first = try #require(service.events.first { $0.name == "video_watched" })
        #expect(first.properties["video_id"] == .string("a"))
        #expect(first.properties["watch_ms"] == .int(3500))
        #expect(first.properties["duration_ms"] == .int(10_000))
        #expect(first.properties["exit_position_ms"] == .int(2500))
        #expect(first.properties["exit"] == .string("swipe"))
        #expect(first.properties["author_id"] == .string("bob-id"))

        clock.advance(by: 4)
        viewModel.setActive(false)
        let second = try #require(service.events.last)
        #expect(second.properties["video_id"] == .string("b"))
        #expect(second.properties["exit"] == .string("leave"))
        #expect(second.properties["watch_ms"] == .int(4000))
    }

    @Test("source du visionnage : feed principal, feeds des abonnements (ADR-048) et des amis (ADR-054), liste")
    func watchSource() async throws {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        for (mode, source) in [
            (FeedViewModel.Mode.endlessFeed, "feed"), (.followingFeed, "following"), (.friendsFeed, "friends"),
            (.list(page(["a"], next: nil), startIndex: 0), "list"),
        ] {
            let viewModel = FeedViewModel(
                loadPage: LoadFeedPageUseCase(feed: FakeFeedRepository([.success(page(["a"], next: nil))])),
                recordView: RecordViewUseCase(history: FakeViewHistoryRepository()),
                playback: playback, session: session, analytics: makeAnalytics(service), mode: mode,
                viewDelay: .milliseconds(10), now: { [clock] in clock.now })
            await viewModel.start()
            clock.advance(by: 2)
            viewModel.setActive(false)
            let watched = try #require(service.events.last { $0.name == "video_watched" })
            #expect(watched.properties["source"] == .string(source))
        }
    }

    @Test("visionnage commencé avant le consentement : pas envoyé ; le suivant l'est")
    func watchBeforeConsent() async {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let analytics = makeAnalytics(service, consent: nil)
        let viewModel = FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: FakeFeedRepository([.success(page(["a", "b", "c"], next: nil))])),
            recordView: RecordViewUseCase(history: FakeViewHistoryRepository()),
            playback: playback,
            session: session,
            analytics: analytics,
            now: { [clock] in clock.now }
        )
        await viewModel.start()
        clock.advance(by: 5)
        analytics.setConsent(true)
        viewModel.show(viewModel.entries[1].id)
        clock.advance(by: 2)
        viewModel.show(viewModel.entries[2].id)
        #expect(service.events.map { $0.properties["video_id"] } == [.string("b")])
    }

    @Test("invité, variante : la connexion s'ouvre avec l'invitation après 5 vidéos regardées")
    func guestPrompt() async throws {
        service.flags[GuestPromptExperiment.flag] = GuestPromptExperiment.promptVariant
        let ids = ["a", "b", "c", "d", "e", "f"]
        let (viewModel, session) = await makeFeed(ids, signedIn: false)
        await viewModel.start()
        for (index, entry) in viewModel.entries.enumerated() where index < 5 {
            if index > 0 { viewModel.show(entry.id) }
            #expect(!session.isPresentingSignIn)
            // Attendre que la vidéo soit comptée (délai de lecture), quelle que soit la charge de la machine.
            #expect(await eventually { viewModel.guestWatchedCount == index + 1 })
        }
        #expect(await eventually { session.isPresentingSignIn })
        #expect(session.signInMessage == GuestPromptExperiment.message)
        #expect(service.eventNames.contains("guest_prompt_shown"))
        // Fermée : l'invitation disparaît.
        session.isPresentingSignIn = false
        #expect(session.signInMessage == nil)
    }

    @Test("invité, témoin : pas d'invitation, exposition enregistrée")
    func guestControl() async throws {
        service.flags[GuestPromptExperiment.flag] = "control"
        let (viewModel, session) = await makeFeed(["a", "b", "c", "d", "e"], signedIn: false)
        await viewModel.start()
        for (index, entry) in viewModel.entries.enumerated() {
            if index > 0 { viewModel.show(entry.id) }
            #expect(await eventually { viewModel.guestWatchedCount == index + 1 })
        }
        #expect(await eventually { service.flagReads == [GuestPromptExperiment.flag] })
        #expect(!session.isPresentingSignIn)
    }

    @Test("engagement : réaction au double toucher, follow, partage")
    func engagement() async {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let repository = FakeInteractionRepository()
        let model = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: repository),
            setFollow: SetFollowUseCase(interactions: repository),
            recordShare: ShareVideoUseCase(interactions: repository),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            session: session,
            analytics: makeAnalytics(service)
        )
        let video = FeedVideo.sample("v1", viewer: .empty)
        _ = await model.likeFromDoubleTap(video)
        _ = await model.toggleFollow(authorOf: video)
        await model.shareCompleted(video)
        #expect(service.eventNames == ["video_reaction", "follow_changed", "video_shared"])
        #expect(service.events[0].properties["trigger"] == .string("double_tap"))
        #expect(service.events[0].properties["kind"] == .string("like"))
        #expect(service.events[2].properties["method"] == .string("system"))
    }

    @Test("connexion : événement envoyé avant l'identification du compte")
    func login() async {
        let session = makeSession(auth: FakeAuthRepository(hasSession: false))
        await session.restore()
        let analytics = makeAnalytics(service)
        let viewModel = LoginViewModel(
            login: LoginUseCase(auth: FakeAuthRepository(), profiles: FakeProfileRepository()), session: session, analytics: analytics)
        viewModel.identifier = "alice@test.local"
        viewModel.password = "password"
        await viewModel.submit()
        #expect(service.eventNames == ["login_completed"])
        #expect(service.identified.isEmpty)
        analytics.sessionChanged(userID: session.profile?.id)
        #expect(service.identified == [UserProfile.alice.id])
    }
}
