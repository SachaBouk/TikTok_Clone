import SwiftUI

// Connexion et inscription (ADR-055) : écran « Connexion » (ou « Inscription »), puis le formulaire de connexion ou les
// étapes de l'inscription, poussés dans la même pile de navigation (bouton retour natif). Deux usages :
// - feuille ouverte par une action d'invité (`.prompt`), avec « Fermer » ;
// - fin de l'onboarding du premier lancement (`.onboarding`), avec « Continuer sans compte ».
struct AuthFlowView: View {
    enum Route: Hashable {
        case login
        case signup(SignupStep)
    }

    let container: AppContainer
    var source: AuthSource = .prompt
    // Onboarding : « Continuer sans compte ».
    var skip: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var path: [Route] = []
    // Créé à la première ouverture de l'inscription, gardé pour tout le parcours (retour en arrière compris).
    @State private var signup: SignupFlowModel?

    var body: some View {
        NavigationStack(path: $path) {
            AuthWelcomeView(mode: .login, invitation: session.signInMessage)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .login:
                        LoginView(viewModel: container.makeLoginViewModel())
                    case .signup(let step):
                        if let signup {
                            signupScreen(step, model: signup)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if let skip {
                            Button("Continuer sans compte", action: skip)
                                .accessibilityIdentifier("onboarding.skip")
                        } else {
                            Button("Fermer", systemImage: "xmark") { dismiss() }
                                .accessibilityIdentifier("auth.close")
                        }
                    }
                }
        }
        // Compte créé : la fin du parcours (intérêts, tutoriel) ne se ferme pas par un glissement.
        .interactiveDismissDisabled(signup?.accountCreated == true)
        // Parcours d'onboarding (ADR-013).
        .onAppear { container.analytics.track(.authSheetShown(source: source)) }
        .onChange(of: path) { _, path in
            if path.contains(.signup(.birthday)), signup == nil {
                signup = container.makeSignupFlowModel()
                container.analytics.track(.signupStarted)
            }
        }
        // Présentée aussi depuis d'autres feuilles (commentaires) : se ferme d'elle-même une fois connecté.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn, skip == nil { dismiss() }
        }
    }

    @ViewBuilder
    private func signupScreen(_ step: SignupStep, model: SignupFlowModel) -> some View {
        switch step {
        case .birthday: SignupBirthdayView(model: model, next: show)
        case .email: SignupEmailView(model: model, next: show)
        case .password: SignupPasswordView(model: model, next: show)
        case .username: SignupUsernameView(model: model, next: show)
        case .interests: SignupInterestsView(model: model, next: show)
        case .tutorial: SignupTutorialView(model: model)
        }
    }

    // Étape suivante, ou retour à une étape déjà passée (email déjà pris, découvert à la création du compte).
    private func show(_ step: SignupStep) {
        if let index = path.firstIndex(of: .signup(step)) {
            path.removeSubrange((index + 1)...)
        } else {
            path.append(.signup(step))
        }
    }
}
