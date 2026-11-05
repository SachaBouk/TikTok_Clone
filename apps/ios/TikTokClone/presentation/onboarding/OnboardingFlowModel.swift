import Foundation
import Observation

// Parcours de l'onboarding animé (ADR-075) : écrans empilés dans `navigation` (racine : l'accueil), réponses aux
// questions, inscription (`SignupFlowModel`, ADR-055), tutoriels, consentement et paywall « Plus ».
// Sert aussi, sans l'accueil ni les questions, à la fin d'une inscription ouverte depuis la feuille d'un invité
// (`promptSignup`) et à « Revoir la présentation » (`replay`).
@MainActor
@Observable
final class OnboardingFlowModel {
    var navigation: [OnboardingStep]
    private(set) var path: OnboardingPath
    private(set) var answers: OnboardingAnswers
    private(set) var signup: SignupFlowModel?
    private(set) var tutorialsCompleted: Set<OnboardingStep> = []
    private(set) var isFinished = false
    // Mesure d'audience pas encore tranchée au début : l'écran du consentement fait partie du parcours.
    let asksConsent: Bool

    @ObservationIgnored let feedback: OnboardingFeedback?
    private let preferences: any PreferencesStore
    private let analytics: AnalyticsModel
    private let makeSignup: () -> SignupFlowModel
    private let onFinish: () -> Void
    private let now: () -> Date
    private let startedAt: Date

    init(
        path: OnboardingPath = .signup, signup: SignupFlowModel? = nil, preferences: any PreferencesStore, analytics: AnalyticsModel,
        feedback: OnboardingFeedback?, makeSignup: @escaping () -> SignupFlowModel, now: @escaping () -> Date = { Date() },
        onFinish: @escaping () -> Void
    ) {
        self.path = path
        self.signup = signup
        self.preferences = preferences
        self.analytics = analytics
        self.feedback = feedback
        self.makeSignup = makeSignup
        self.now = now
        self.onFinish = onFinish
        answers = preferences.onboardingAnswers
        asksConsent = analytics.consent == nil && path != .replay
        startedAt = now()
        navigation = []
        // Hors du premier lancement, le parcours commence directement à la fin (tutoriels).
        if path == .promptSignup || path == .replay, let first = finale.first {
            navigation = [first]
        }
    }

    var steps: [OnboardingStep] {
        OnboardingJourney.steps(path: path, goal: answers.goal, askConsent: asksConsent)
    }

    var finale: [OnboardingStep] {
        OnboardingJourney.finale(path: path, goal: answers.goal, askConsent: asksConsent)
    }

    var current: OnboardingStep { navigation.last ?? .welcome }

    func progress(of step: OnboardingStep) -> Double? {
        guard OnboardingJourney.showsProgress(step) else { return nil }
        return OnboardingJourney.progress(of: step, in: steps)
    }

    func canGoBack(from step: OnboardingStep) -> Bool {
        OnboardingJourney.canGoBack(from: step) && !navigation.isEmpty
    }

    func offersGuestExit(_ step: OnboardingStep) -> Bool {
        OnboardingJourney.offersGuestExit(step, path: path) && signup?.accountCreated != true
    }

    func viewed(_ step: OnboardingStep) {
        analytics.track(.onboardingStepViewed(step))
    }

    // MARK: Accueil

    // « C'est parti ».
    func start() {
        path = .signup
        go(to: .hello)
    }

    // « J'ai déjà un compte ».
    func chooseLogin() {
        path = .login
        go(to: .login)
    }

    // MARK: Questions

    func choose(_ source: OnboardingSource) {
        guard answers.source != source else { return }
        answers.source = source
        preferences.setOnboardingAnswers(answers)
        feedback?.play(.select)
    }

    func choose(_ goal: OnboardingGoal) {
        guard answers.goal != goal else { return }
        answers.goal = goal
        preferences.setOnboardingAnswers(answers)
        feedback?.play(.select)
    }

    // MARK: Navigation

    // Écran suivant du chemin ; à la fin, le parcours se termine.
    func next(from step: OnboardingStep) {
        guard let next = OnboardingJourney.step(after: step, in: steps) else { return finish() }
        go(to: next)
    }

    func go(to step: OnboardingStep) {
        if step == .birthday, signup == nil {
            signup = makeSignup()
            analytics.track(.signupStarted)
        }
        navigation.append(step)
        feedback?.play(.advance)
    }

    func back() {
        guard canGoBack(from: current) else { return }
        navigation.removeLast()
        // L'écran de préparation avance tout seul : il est sauté.
        while let last = navigation.last, OnboardingJourney.skippedWhenGoingBack(last) {
            navigation.removeLast()
        }
        feedback?.play(.tap)
    }

    // Étape suivante demandée par un écran de l'inscription (ADR-055). Le pseudo confirmé (compte créé) mène à l'écran
    // « Bienvenue » ; les centres d'intérêt mènent aux tutoriels ; un email déjà pris ramène à son étape.
    func signupAdvanced(to signupStep: SignupStep) {
        switch signupStep {
        case .interests where !navigation.contains(.accountCreated) && path != .promptSignup:
            feedback?.play(.celebrate)
            navigation.append(.accountCreated)
        case .tutorial:
            next(from: .interests)
        default:
            guard let step = OnboardingStep(signupStep) else { return }
            if let index = navigation.firstIndex(of: step) {
                navigation.removeSubrange((index + 1)...)
                feedback?.play(.error)
            } else {
                go(to: step)
            }
        }
    }

    // « Plus tard » pendant l'inscription : invité, tutoriels puis consentement.
    func continueAsGuest() {
        path = .guest
        signup = nil
        next(from: .birthday)
    }

    // MARK: Tutoriels, consentement, paywall

    func tutorialCompleted(_ step: OnboardingStep) {
        guard tutorialsCompleted.insert(step).inserted else { return }
        feedback?.play(.success)
    }

    func answerConsent(_ granted: Bool) {
        analytics.setConsent(granted)
        next(from: .consent)
    }

    // Connexion réussie (« J'ai déjà un compte ») : consentement s'il n'est pas tranché, sinon fin.
    func loggedIn() {
        guard path == .login, current == .login else { return }
        next(from: .login)
    }

    // Paywall affiché : la session du compte créé est annoncée (l'achat demande un compte connecté, ADR-073).
    func paywallShown() {
        signup?.announceSession()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        let duration = Int(now().timeIntervalSince(startedAt))
        analytics.track(
            .onboardingCompleted(path: path, answers: answers, durationSeconds: duration, tutorialsCompleted: tutorialsCompleted.count))
        if path == .signup || path == .promptSignup { signup?.finish() }
        onFinish()
    }
}
