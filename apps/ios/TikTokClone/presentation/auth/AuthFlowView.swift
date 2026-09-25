import SwiftUI

// Feuille de connexion : connexion par email, et inscription poussée dans la même pile de navigation
// (bouton retour natif).
struct AuthFlowView: View {
    enum Route: Hashable {
        case register
    }

    let container: AppContainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginView(viewModel: container.makeLoginViewModel())
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .register: RegisterView(viewModel: container.makeRegisterViewModel())
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
    }
}
