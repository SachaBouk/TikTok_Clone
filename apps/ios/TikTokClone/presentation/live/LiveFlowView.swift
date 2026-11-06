import LiveSDK
import LiveSDKUI
import SwiftUI

// Live commun (ADR-079) : écrans du SDK d'echimine (`LiveSDKUI`), reliés au serveur hébergé `live.echimine.fr`, en plein
// écran à la racine (`AppRouter.presentedLive`). La navigation entre eux est à l'app : liste → live ou lancement,
// lancement → son live ; fermer un live ouvert depuis la liste y revient, sinon le plein écran se ferme.
extension View {
    func livePresenter(_ container: AppContainer) -> some View {
        modifier(LivePresenter(container: container))
    }
}

private struct LivePresenter: ViewModifier {
    let container: AppContainer

    func body(content: Content) -> some View {
        @Bindable var router = container.router
        content.fullScreenCover(item: $router.presentedLive) { route in
            LiveFlowView(route: route, container: container) { router.presentedLive = nil }
        }
    }
}

// Thème des écrans du SDK : accent rose de l'app, libellé du Live.
extension LiveTheme {
    static let tikTokClone = LiveTheme(accent: .brandPink, cornerRadius: 12, fontName: nil, label: "TikTok Clone Live")
}

struct LiveFlowView: View {
    let route: AppRouter.LiveRoute
    let container: AppContainer
    let onDismiss: () -> Void

    // Écran affiché ; `fromList` : fermer revient à la liste.
    private enum Screen {
        case list
        case launch(fromList: Bool)
        case live(id: String, fromList: Bool)
        case session(LiveSession, fromList: Bool)
    }

    @State private var screen: Screen?
    @State private var isReady = false
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !session.isSignedIn {
                signedOut
            } else if isReady, let screen {
                content(screen)
                    .liveTheme(.tikTokClone)
            } else {
                DotsLoader()
            }
        }
        .task {
            if screen == nil { screen = initialScreen() }
            await container.prepareLive()
            isReady = true
        }
    }

    private func initialScreen() -> Screen {
        switch route.content {
        case .list:
            return .list
        case .launch:
            return .launch(fromList: false)
        case .watch(let id, let source):
            opened(source: source)
            return .live(id: id, fromList: false)
        }
    }

    @ViewBuilder
    private func content(_ screen: Screen) -> some View {
        switch screen {
        case .list:
            NavigationStack {
                LiveListScreen { id in
                    opened(source: .discover)
                    self.screen = .live(id: id, fromList: true)
                } onLaunch: {
                    self.screen = .launch(fromList: true)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer", systemImage: "xmark", action: onDismiss)
                            .accessibilityIdentifier("live.list.close")
                    }
                }
            }
        case .launch(let fromList):
            LiveLaunchScreen { liveSession in
                container.analytics.track(.liveStarted)
                self.screen = .session(liveSession, fromList: fromList)
            } onClose: {
                close(fromList: fromList)
            }
        case .live(let id, let fromList):
            LiveScreen(liveId: id) { close(fromList: fromList) }
                .id(id)
        case .session(let liveSession, let fromList):
            LiveScreen(session: liveSession) { close(fromList: fromList) }
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("Connecte-toi pour regarder et lancer des lives.")
        } actions: {
            Button("Se connecter") {
                onDismiss()
                Task {
                    // La connexion s'ouvre une fois le plein écran fermé.
                    try? await Task.sleep(for: .milliseconds(600))
                    session.requestSignIn(message: "Connecte-toi pour regarder et lancer des lives.")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPink)
            Button("Fermer", action: onDismiss)
                .tint(.white)
        }
        .foregroundStyle(.white)
    }

    private func close(fromList: Bool) {
        if fromList { screen = .list } else { onDismiss() }
    }

    private func opened(source: LiveSource) {
        container.analytics.track(.liveViewed(source: source))
    }
}
