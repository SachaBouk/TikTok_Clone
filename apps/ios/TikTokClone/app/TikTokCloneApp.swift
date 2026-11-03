import SwiftUI

@main
struct TikTokCloneApp: App {
    // Orientation de l'interface (plein écran en paysage) : `OrientationLock`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer(configuration: .fromBundle())

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .environment(container.session)
                .environment(container.analytics)
        }
    }
}
