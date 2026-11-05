import Foundation

// Onboarding animé (ADR-075) : écrans du parcours, réponses aux questions et règles de navigation. Règles pures,
// testées sans SwiftUI.

// « Comment as-tu connu TikTok Clone ? »
enum OnboardingSource: String, CaseIterable, Codable, Sendable {
    case friends, social
    case appStore = "app_store"
    case web, video, other
}

// « Tu viens surtout pour… »
enum OnboardingGoal: String, CaseIterable, Codable, Sendable {
    case watch, create, both

    // « Créer et publier » ou « Les deux » : le tutoriel de création s'ajoute.
    var includesCreation: Bool { self != .watch }
}

// Réponses gardées sur l'iPhone (jamais envoyées à l'API).
struct OnboardingAnswers: Codable, Equatable, Sendable {
    var source: OnboardingSource?
    var goal: OnboardingGoal?
}

// Chemin suivi dans le parcours.
enum OnboardingPath: String, Sendable {
    // « C'est parti », puis inscription.
    case signup
    // « J'ai déjà un compte ».
    case login
    // « Plus tard » pendant l'inscription : invité.
    case guest
    // Inscription depuis la feuille d'un invité (ADR-055), plus tard.
    case promptSignup = "prompt_signup"
    // « Revoir la présentation » (paramètres) : les tutoriels seulement.
    case replay
}

enum OnboardingStep: String, Hashable, Sendable, CaseIterable {
    case welcome, hello, source, goal, preparing
    case birthday, email, password, username
    case accountCreated = "account_created"
    case interests
    case login
    case swipeUp = "swipe_up"
    case doubleTapLike = "double_tap_like"
    case fastForward = "fast_forward"
    case
        swipeToProfile = "swipe_to_profile"
    case create
    case consent, plus

    var isTutorial: Bool { OnboardingJourney.tutorials(goal: .both).contains(self) }

    // Étape de l'inscription (ADR-055) correspondante.
    var signupStep: SignupStep? {
        switch self {
        case .birthday: .birthday
        case .email: .email
        case .password: .password
        case .username: .username
        case .interests: .interests
        default: nil
        }
    }

    init?(_ signupStep: SignupStep) {
        switch signupStep {
        case .birthday: self = .birthday
        case .email: self = .email
        case .password: self = .password
        case .username: self = .username
        case .interests: self = .interests
        case .tutorial: return nil
        }
    }
}

enum OnboardingJourney {
    static let questions: [OnboardingStep] = [.welcome, .hello, .source, .goal, .preparing]
    static let signupSteps: [OnboardingStep] = [.birthday, .email, .password, .username, .accountCreated, .interests]

    static func tutorials(goal: OnboardingGoal?) -> [OnboardingStep] {
        [.swipeUp, .doubleTapLike, .fastForward, .swipeToProfile] + (goal?.includesCreation == true ? [.create] : [])
    }

    // Tous les écrans du chemin, dans l'ordre. `askConsent` : la mesure d'audience n'a pas encore été tranchée.
    static func steps(path: OnboardingPath, goal: OnboardingGoal?, askConsent: Bool) -> [OnboardingStep] {
        let consent: [OnboardingStep] = askConsent ? [.consent] : []
        switch path {
        case .signup:
            return questions + signupSteps + tutorials(goal: goal) + consent + [.plus]
        case .guest:
            // L'invité quitte l'inscription à la date de naissance (« Plus tard »).
            return questions + [.birthday] + tutorials(goal: goal) + consent
        case .login:
            return [.welcome, .login] + consent
        case .promptSignup:
            return signupSteps + tutorials(goal: goal) + consent + [.plus]
        case .replay:
            return tutorials(goal: goal)
        }
    }

    // Écrans qui suivent la création du compte (ou le départ de l'invité), joués d'affilée.
    static func finale(path: OnboardingPath, goal: OnboardingGoal?, askConsent: Bool) -> [OnboardingStep] {
        let all = steps(path: path, goal: goal, askConsent: askConsent)
        guard let first = all.firstIndex(where: { $0.isTutorial || $0 == .consent || $0 == .plus }) else { return [] }
        return Array(all[first...])
    }

    // Écran suivant, nil à la fin du parcours.
    static func step(after step: OnboardingStep, in steps: [OnboardingStep]) -> OnboardingStep? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    // Avancement de la barre du haut (0 à 1), d'après la place de l'écran dans le chemin.
    static func progress(of step: OnboardingStep, in steps: [OnboardingStep]) -> Double {
        guard let index = steps.firstIndex(of: step), steps.count > 1 else { return 0 }
        return Double(index) / Double(steps.count - 1)
    }

    // Barre de progression : pas sur l'accueil ni sur la connexion.
    static func showsProgress(_ step: OnboardingStep) -> Bool {
        step != .welcome && step != .login
    }

    // ‹ : jusqu'à la création du compte seulement ; ni après (compte créé), ni dans les tutoriels.
    static func canGoBack(from step: OnboardingStep) -> Bool {
        switch step {
        case .hello, .source, .goal, .birthday, .email, .password, .username, .login: true
        default: false
        }
    }

    // « Plus tard » : pendant l'inscription, avant la création du compte (parcours du premier lancement seulement).
    static func offersGuestExit(_ step: OnboardingStep, path: OnboardingPath) -> Bool {
        path == .signup && [.birthday, .email, .password, .username].contains(step)
    }

    // Écran sauté en revenant en arrière : l'écran de préparation avance tout seul.
    static func skippedWhenGoingBack(_ step: OnboardingStep) -> Bool {
        step == .preparing
    }
}
