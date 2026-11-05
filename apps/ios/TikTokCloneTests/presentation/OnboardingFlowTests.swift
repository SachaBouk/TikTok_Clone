import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Onboarding animé : parcours (ADR-075)")
struct OnboardingFlowTests {
    let auth = FakeAuthRepository()
    let signupRepository = FakeSignupRepository()
    let service = FakeAnalyticsService()

    func makeSignup(session: SessionStore, analytics: AnalyticsModel) -> SignupFlowModel {
        let now = SignupTests.now
        return SignupFlowModel(
            register: RegisterUseCase(auth: auth, profiles: FakeProfileRepository(), today: { BirthDate(now) }),
            checkUsername: CheckUsernameUseCase(signup: signupRepository),
            loadCatalog: LoadInterestCatalogUseCase(signup: signupRepository),
            saveInterests: SaveInterestsUseCase(signup: signupRepository),
            session: session, analytics: analytics, today: { now }, usernameDebounce: .zero)
    }

    func makeFlow(
        path: OnboardingPath = .signup, consent: Bool? = nil, preferences: InMemoryPreferencesStore? = nil, onFinish: @escaping () -> Void = {}
    ) -> (OnboardingFlowModel, SessionStore, SilentSoundPlayer, AnalyticsModel) {
        let session = makeSession(auth: auth)
        let preferences = preferences ?? InMemoryPreferencesStore(consent: consent)
        let analytics = AnalyticsModel(service: service, preferences: preferences)
        let sounds = SilentSoundPlayer()
        let flow = OnboardingFlowModel(
            path: path, preferences: preferences, analytics: analytics, feedback: OnboardingFeedback(sounds: sounds),
            makeSignup: { [self] in makeSignup(session: session, analytics: analytics) }, onFinish: onFinish)
        return (flow, session, sounds, analytics)
    }

    @Test("questions : réponses gardées sur l'iPhone, son à chaque choix ; « créer » ajoute le tutoriel de création")
    func questions() {
        let preferences = InMemoryPreferencesStore()
        let (flow, _, sounds, _) = makeFlow(preferences: preferences)
        flow.start()
        #expect(flow.navigation == [.hello])
        flow.next(from: .hello)
        flow.choose(OnboardingSource.friends)
        flow.choose(OnboardingSource.friends)
        flow.next(from: .source)
        flow.choose(OnboardingGoal.create)
        #expect(preferences.onboardingAnswers == OnboardingAnswers(source: .friends, goal: .create))
        #expect(sounds.played.filter { $0 == .select }.count == 2)
        #expect(flow.steps.contains(.create))
        #expect(flow.steps.contains(.consent))
    }

    @Test("retour : l'écran de préparation est sauté, pas de retour après la création du compte")
    func back() {
        let (flow, _, _, _) = makeFlow()
        flow.start()
        flow.next(from: .hello)
        flow.next(from: .source)
        flow.next(from: .goal)
        flow.next(from: .preparing)
        #expect(flow.current == .birthday)
        #expect(flow.signup != nil)
        flow.back()
        #expect(flow.current == .goal)
        flow.navigation.append(.accountCreated)
        flow.back()
        #expect(flow.current == .accountCreated)
    }

    @Test("inscription complète : « Bienvenue », tutoriels, consentement, session annoncée au paywall, fin")
    func signupThroughPaywall() async throws {
        var finished = false
        let (flow, session, _, analytics) = makeFlow(consent: nil) { finished = true }
        flow.start()
        flow.next(from: .hello)
        flow.choose(OnboardingGoal.watch)
        flow.go(to: .birthday)
        let signup = try #require(flow.signup)
        signup.birthDate = SignupTests.now.addingTimeInterval(-20 * 365 * 86_400)
        signup.email = "lea@demo.local"
        signup.password = "motdepasse1"
        signup.username = "lea.m"
        await signup.usernameChanged()
        let step = await signup.submit()
        flow.signupAdvanced(to: try #require(step))
        #expect(flow.current == .accountCreated)
        flow.next(from: .accountCreated)
        #expect(flow.current == .interests)
        flow.signupAdvanced(to: .tutorial)
        #expect(flow.current == .swipeUp)
        flow.tutorialCompleted(.swipeUp)
        flow.tutorialCompleted(.swipeUp)
        #expect(flow.tutorialsCompleted == [.swipeUp])
        for tutorial in [OnboardingStep.swipeUp, .doubleTapLike, .fastForward, .swipeToProfile] { flow.next(from: tutorial) }
        #expect(flow.current == .consent)
        #expect(!session.isSignedIn)
        flow.answerConsent(true)
        #expect(analytics.consent == true)
        #expect(flow.current == .plus)
        flow.paywallShown()
        #expect(session.isSignedIn)
        #expect(!finished)
        flow.finish()
        flow.finish()
        #expect(finished)
        let completed = service.events.filter { $0.name == "onboarding_completed" }
        #expect(completed.count == 1)
        #expect(completed.first?.properties["path"] == .string("signup"))
        #expect(completed.first?.properties["goal"] == .string("watch"))
        #expect(completed.first?.properties["tutorials_completed"] == .int(1))
    }

    @Test("email déjà pris : retour à son étape, son d'erreur")
    func emailTaken() {
        let (flow, _, sounds, _) = makeFlow()
        flow.go(to: .birthday)
        flow.signupAdvanced(to: .email)
        flow.signupAdvanced(to: .password)
        flow.signupAdvanced(to: .username)
        flow.signupAdvanced(to: .email)
        #expect(flow.navigation == [.birthday, .email])
        #expect(sounds.played.last == .error)
    }

    @Test("« Plus tard » : invité, tutoriels puis consentement, sans paywall")
    func guest() {
        var finished = false
        let (flow, session, _, _) = makeFlow(consent: false) { finished = true }
        flow.start()
        flow.go(to: .birthday)
        #expect(flow.offersGuestExit(.birthday))
        flow.continueAsGuest()
        #expect(flow.path == .guest)
        #expect(flow.current == .swipeUp)
        for tutorial in OnboardingJourney.tutorials(goal: nil) { flow.next(from: tutorial) }
        #expect(finished)
        #expect(!session.isSignedIn)
    }

    @Test("« J'ai déjà un compte » : connexion, puis consentement s'il n'est pas tranché")
    func login() {
        var finished = false
        let (flow, _, _, _) = makeFlow(consent: nil) { finished = true }
        flow.chooseLogin()
        #expect(flow.current == .login)
        #expect(flow.progress(of: .login) == nil)
        flow.loggedIn()
        #expect(flow.current == .consent)
        flow.answerConsent(false)
        #expect(finished)
    }

    @Test("« Revoir la présentation » : les tutoriels seulement, sans consentement")
    func replay() {
        var finished = false
        let (flow, _, _, _) = makeFlow(path: .replay, consent: nil) { finished = true }
        #expect(flow.current == .swipeUp)
        #expect(!flow.asksConsent)
        for tutorial in OnboardingJourney.tutorials(goal: nil) { flow.next(from: tutorial) }
        #expect(finished)
    }

    @Test("feed en pause sous l'onboarding : il couvre les onglets")
    func feedPausedUnderOnboarding() {
        let router = AppRouter()
        #expect(!router.coversTabs)
        router.isOnboardingShown = true
        #expect(router.coversTabs)
    }
}
