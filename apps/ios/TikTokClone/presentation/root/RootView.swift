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
        // Session reprise : onboarding du premier lancement (ADR-055), puis consentement à la mesure d'audience
        // (ADR-013), après l'onboarding et pas par-dessus.
        .onChange(of: session.state == .restoring) { _, restoring in
            guard !restoring, session.state != .unavailable else { return }
            // Sans l'animation de présentation (glissement depuis le bas) : l'introduction remplace l'écran de lancement.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { container.onboarding.sessionRestored(signedIn: session.isSignedIn) }
            if !container.onboarding.isPresented { analytics.askConsentIfNeeded() }
        }
        // Consentement demandé une fois le plein écran fermé : une feuille présentée pendant sa fermeture est ignorée.
        .fullScreenCover(
            isPresented: Binding(get: { container.onboarding.isPresented }, set: { if !$0 { finishOnboarding() } }),
            onDismiss: { analytics.askConsentIfNeeded() }
        ) {
            OnboardingView(container: container) { finishOnboarding() }
                .environment(session)
                .environment(analytics)
                // Connexion ou inscription faite pendant l'onboarding : il se termine.
                .onChange(of: session.isSignedIn) { _, signedIn in
                    if signedIn { finishOnboarding() }
                }
        }
        .onChange(of: session.profile?.id, initial: true) { _, userID in
            analytics.sessionChanged(userID: userID)
            // Achats rattachés au compte connecté (ADR-009).
            Task { await container.wallet.sessionChanged(userID: userID) }
        }
        .sheet(
            isPresented: Binding(
                get: { analytics.isAskingConsent },
                set: { analytics.isAskingConsent = $0 }
            )
        ) {
            AnalyticsConsentView()
        }
    }

    private func finishOnboarding() {
        guard container.onboarding.isPresented else { return }
        container.onboarding.finish()
    }
}
