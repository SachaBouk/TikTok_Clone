import SwiftUI

@main
struct TikTokCloneApp: App {
    // Orientation de l'interface (plein écran en paysage) : `OrientationLock`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container: AppContainer

    init() {
        #if DEBUG
            // `-resetOnboarding` (ADR-075) : l'onboarding animé, son consentement et l'indication du feed reviennent.
            // Une session enregistrée (trousseau) le saute toujours : se déconnecter d'abord.
            if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") { UserDefaultsPreferencesStore().resetOnboarding() }
        #endif
        _container = State(initialValue: AppContainer(configuration: .fromBundle()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .environment(container.session)
                .environment(container.analytics)
        }
    }
}
