import SwiftUI

struct RootView: View {
    let container: AppContainer
    @Environment(SessionStore.self) private var session

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
        .onOpenURL { container.router.open($0) }
    }
}
