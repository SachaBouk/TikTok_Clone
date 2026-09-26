import SwiftUI

struct RootView: View {
    let container: AppContainer
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView()
            case .unavailable:
                ContentUnavailableView {
                    Label("Serveur injoignable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Impossible de reprendre ta session. Vérifie ta connexion.")
                } actions: {
                    Button("Réessayer") { Task { await session.restore() } }
                        .buttonStyle(.borderedProminent)
                    Button("Continuer sans compte") { session.continueAsGuest() }
                }
            case .guest, .signedIn:
                MainTabView(container: container)
            }
        }
        .task { await session.restore() }
        // Temps réel et reprise des publications : compte connecté et app au premier plan.
        .onChange(of: [session.isSignedIn, scenePhase == .active], initial: true) { _, state in
            container.activityChanged(signedIn: state[0], active: state[1])
        }
        .onOpenURL { container.router.open($0) }
    }
}
