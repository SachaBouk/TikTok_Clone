import SwiftUI

@main
struct TikTokCloneApp: App {
    @State private var container = AppContainer(configuration: .fromBundle())

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .environment(container.session)
        }
    }
}
