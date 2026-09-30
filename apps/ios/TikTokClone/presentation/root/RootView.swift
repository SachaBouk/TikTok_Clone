import SwiftUI

struct RootView: View {
    let container: AppContainer
    @Environment(SessionStore.self) private var session
    @Environment(AnalyticsModel.self) private var analytics
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                LaunchView()
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
        // Mesure d'audience (ADR-013) : consentement demandé une fois la session reprise, compte identifié.
        .onChange(of: session.state == .restoring) { _, restoring in
            if !restoring { analytics.askConsentIfNeeded() }
        }
        .onChange(of: session.profile?.id, initial: true) { _, userID in
            analytics.sessionChanged(userID: userID)
            // Achats rattachés au compte connecté (ADR-009).
            Task { await container.wallet.sessionChanged(userID: userID) }
        }
        .sheet(isPresented: Binding(
            get: { analytics.isAskingConsent },
            set: { analytics.isAskingConsent = $0 }
        )) {
            AnalyticsConsentView()
        }
    }
}
