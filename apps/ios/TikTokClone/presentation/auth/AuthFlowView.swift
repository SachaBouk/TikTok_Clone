import SwiftUI

// Connexion et inscription (ADR-055) : écran « Connexion » (ou « Inscription »), puis le formulaire, poussé dans la
// même pile de navigation (bouton retour natif). Deux usages :
// - feuille ouverte par une action d'invité (`.prompt`), avec « Fermer » ;
// - fin de l'onboarding du premier lancement (`.onboarding`), avec « Continuer sans compte ».
struct AuthFlowView: View {
    enum Route: Hashable {
        case login
        case register
    }

    let container: AppContainer
    var source: AuthSource = .prompt
    // Onboarding : « Continuer sans compte ».
    var skip: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            AuthWelcomeView(mode: .login, invitation: session.signInMessage)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .login:
                        LoginView(viewModel: container.makeLoginViewModel())
                    case .register:
                        RegisterView(viewModel: container.makeRegisterViewModel())
                            .onAppear { container.analytics.track(.signupStarted) }
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
        // Parcours d'onboarding (ADR-013).
        .onAppear { container.analytics.track(.authSheetShown(source: source)) }
        // Présentée aussi depuis d'autres feuilles (commentaires) : se ferme d'elle-même une fois connecté.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn, skip == nil { dismiss() }
        }
    }
}
