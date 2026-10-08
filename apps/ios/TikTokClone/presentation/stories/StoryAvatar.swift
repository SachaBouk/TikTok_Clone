import SwiftUI

// Photo de profil entourée de l'anneau des stories (ADR-051) : coloré pour une story à voir, gris pour une story déjà vue,
// absent sans story.
struct StoryAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat
    let ring: StoryRing?

    var body: some View {
        AvatarView(url: url, name: name, size: size)
            .padding(ring == nil ? 0 : ringWidth + 2)
            .overlay {
                switch ring {
                case .unseen:
                    Circle().strokeBorder(Self.gradient, lineWidth: ringWidth)
                case .seen:
                    Circle().strokeBorder(Color.gray.opacity(0.6), lineWidth: ringWidth * 0.7)
                case nil:
                    EmptyView()
                }
            }
    }

    private var ringWidth: CGFloat { max(2, size * 0.05) }

    static let gradient = AngularGradient(colors: [.pink, .orange, .yellow, .orange, .pink], center: .center)
}

extension View {
    // Visionneuse de stories de `router.presentedStories`. Posée à la racine (onglets) et dans la vidéo seule : un écran
    // plein écran ne peut être présenté que par celui du dessus, `isTopmost` dit lequel présente.
    func storiesPresenter(_ container: AppContainer, isTopmost: @escaping () -> Bool) -> some View {
        modifier(StoriesPresenter(container: container, isTopmost: isTopmost))
    }
}

private struct StoriesPresenter: ViewModifier {
    let container: AppContainer
    let isTopmost: () -> Bool
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        @Bindable var session = session
        content.fullScreenCover(
            item: Binding(
                get: { isTopmost() ? container.router.presentedStories : nil },
                set: { container.router.presentedStories = $0 }
            )
        ) { route in
            StoryViewerView(model: container.makeStoryViewerModel(route), container: container)
                // La connexion doit pouvoir s'ouvrir par-dessus la visionneuse (répondre, aimer en invité).
                .sheet(isPresented: $session.isPresentingSignIn) {
                    AuthFlowView(container: container)
                }
                .environment(session)
                .environment(container.stories)
        }
    }
}
