import SwiftUI

// Onboarding animé du premier lancement (ADR-075, complète ADR-055) : accueil en orbite, Tempo, questions, inscription,
// tutoriels interactifs, consentement et paywall « Plus ». Une pile de navigation sans barre système : chaque écran a
// sa barre du haut (‹, progression). Sons et vibrations actifs le temps du parcours.
struct OnboardingView: View {
    let container: AppContainer
    let finish: () -> Void
    @State private var model: OnboardingFlowModel?

    var body: some View {
        Group {
            if let model {
                OnboardingFlowStack(container: container, model: model)
            } else {
                Color("LaunchBackground").ignoresSafeArea()
            }
        }
        .onAppear {
            if model == nil { model = container.makeOnboardingFlow(path: .signup, onFinish: finish) }
            model?.feedback?.activate()
        }
        .onDisappear { model?.feedback?.deactivate() }
    }
}

private struct OnboardingFlowStack: View {
    let container: AppContainer
    @Bindable var model: OnboardingFlowModel
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack(path: $model.navigation) {
            OnboardingWelcomeView(model: model)
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { model.viewed(.welcome) }
                .navigationDestination(for: OnboardingStep.self) { step in
                    OnboardingStepScreen(container: container, model: model, step: step)
                }
        }
        .environment(\.onboardingFeedback, model.feedback)
        // « J'ai déjà un compte » : connexion réussie.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { model.loggedIn() }
        }
    }
}

// Fin d'une inscription ouverte depuis la feuille d'un invité (`promptSignup`) ou « Revoir la présentation » (`replay`) :
// les écrans du parcours se succèdent sur place, sans pile de navigation.
struct OnboardingSequenceView: View {
    let container: AppContainer
    let model: OnboardingFlowModel

    var body: some View {
        ZStack {
            OnboardingStepScreen(container: container, model: model, step: model.current)
                .id(model.current)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
        }
        .animation(.spring(duration: 0.45, bounce: 0.1), value: model.current)
        .background(Color(.systemBackground))
        .environment(\.onboardingFeedback, model.feedback)
        .onAppear {
            model.feedback?.activate()
            // Fin d'une inscription dans la feuille d'un invité : le feed derrière se met en pause.
            if model.path == .promptSignup { container.router.isOnboardingShown = true }
        }
        .onDisappear {
            model.feedback?.deactivate()
            if model.path == .promptSignup { container.router.isOnboardingShown = false }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled()
    }
}

// Un écran du parcours, avec sa barre du haut.
struct OnboardingStepScreen: View {
    let container: AppContainer
    let model: OnboardingFlowModel
    let step: OnboardingStep

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .top, spacing: 8) { topBar }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .onAppear { model.viewed(step) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView(model: model)
        case .hello:
            OnboardingHelloView(model: model)
        case .source, .goal:
            OnboardingQuestionView(model: model, step: step)
        case .preparing:
            OnboardingPreparingView(model: model)
        case .birthday, .email, .password, .username, .interests:
            if let signup = model.signup {
                SignupStepScreen(model: model, signup: signup, step: step)
            }
        case .accountCreated:
            OnboardingAccountCreatedView(model: model)
        case .login:
            LoginView(viewModel: container.makeLoginViewModel())
        case .swipeUp, .doubleTapLike, .fastForward, .swipeToProfile, .create:
            OnboardingTutorialView(model: model, step: step)
        case .consent:
            OnboardingConsentView(model: model)
        case .plus:
            OnboardingPlusView(model: model, plus: container.plus)
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if step != .welcome && step != .plus {
            OnboardingTopBar(
                progress: model.progress(of: step), back: backAction, trailingTitle: trailingTitle, trailing: trailingAction,
                trailingIdentifier: step.isTutorial ? "onboarding.tutorial.skip" : "onboarding.skip")
        }
    }

    private var backAction: (() -> Void)? {
        guard model.canGoBack(from: step) else { return nil }
        let model = model
        return { model.back() }
    }

    // Tutoriels : « Passer » ; inscription (premier lancement) : « Plus tard », invité.
    private var trailingTitle: String? {
        if step.isTutorial { return "Passer" }
        return model.offersGuestExit(step) ? "Plus tard" : nil
    }

    private var trailingAction: (() -> Void)? {
        let model = model
        let step = step
        if step.isTutorial { return { model.next(from: step) } }
        return model.offersGuestExit(step) ? { model.continueAsGuest() } : nil
    }
}

// Étapes de l'inscription (ADR-055), habillées : Tempo commente chaque étape, sons et vibrations suivent la saisie.
private struct SignupStepScreen: View {
    let model: OnboardingFlowModel
    @Bindable var signup: SignupFlowModel
    let step: OnboardingStep
    @State private var bounce = 0

    var body: some View {
        stepView
            .safeAreaInset(edge: .top, spacing: 0) {
                if step != .interests {
                    TempoSays(text: line, mood: mood, size: 48, bounce: bounce)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }
            }
            .onChange(of: signup.passwordStrength) { old, new in
                guard step == .password, new != old else { return }
                if new == .strong {
                    model.feedback?.play(.success)
                    bounce += 1
                } else if new.rank > old.rank {
                    model.feedback?.play(.tick)
                }
            }
            .onChange(of: signup.usernameStatus) { _, status in
                guard step == .username else { return }
                switch status {
                case .checked(.available):
                    model.feedback?.play(.select)
                    bounce += 1
                case .checked(.taken), .checked(.reserved):
                    model.feedback?.play(.error)
                default:
                    break
                }
            }
            .onChange(of: signup.birthDateProblem) { _, problem in
                if step == .birthday, problem != nil { model.feedback?.play(.error) }
            }
            .onChange(of: signup.usernameError) { _, error in
                if error != nil { model.feedback?.play(.error) }
            }
    }

    @ViewBuilder
    private var stepView: some View {
        let next: (SignupStep) -> Void = { model.signupAdvanced(to: $0) }
        switch step {
        case .birthday: SignupBirthdayView(model: signup, next: next)
        case .email: SignupEmailView(model: signup, next: next)
        case .password: SignupPasswordView(model: signup, next: next)
        case .username: SignupUsernameView(model: signup, next: next)
        default: SignupInterestsView(model: signup, next: next)
        }
    }

    private var line: String {
        switch step {
        case .birthday:
            signup.birthDateProblem == nil ? "Promis, je ne la dirai à personne." : "Il faut avoir 13 ans pour t’inscrire."
        case .email:
            signup.emailError == nil ? "C’est pour te connecter, rien d’autre." : "Cet email a déjà un compte…"
        case .password:
            switch signup.passwordStrength {
            case .none, .weak: "Choisis-le bien !"
            case .medium: "Pas mal ! Encore un effort ?"
            case .strong: "Solide ! 💪"
            }
        default:
            switch signup.usernameStatus {
            case .checked(.available): "Joli pseudo !"
            case .checked(.taken): "Oups, déjà pris…"
            default: "Comment veux-tu qu’on t’appelle ?"
            }
        }
    }

    private var mood: TempoMood {
        switch step {
        case .birthday: signup.birthDateProblem == nil ? .wink : .surprised
        case .email: signup.emailError == nil ? .neutral : .surprised
        case .password: signup.passwordStrength == .strong ? .party : signup.passwordStrength == .medium ? .happy : .thinking
        default:
            switch signup.usernameStatus {
            case .checked(.available): .happy
            case .checked(.taken), .checked(.reserved): .surprised
            default: .neutral
            }
        }
    }
}

extension RegistrationRules.PasswordStrength {
    // Ordre de solidité, pour ne jouer un son qu'en progressant.
    var rank: Int {
        switch self {
        case .none: 0
        case .weak: 1
        case .medium: 2
        case .strong: 3
        }
    }
}

// « Revoir la présentation » (paramètres, ADR-075) : les tutoriels, poussés dans la pile ; la fin revient aux paramètres.
struct TutorialReplayView: View {
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var model: OnboardingFlowModel?

    var body: some View {
        // Un fond toujours présent : un `Group` vide ne déclenche pas `onAppear` (le modèle ne serait jamais créé).
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let model { OnboardingSequenceView(container: container, model: model) }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if model == nil { model = container.makeOnboardingFlow(path: .replay) { dismiss() } }
        }
    }
}
