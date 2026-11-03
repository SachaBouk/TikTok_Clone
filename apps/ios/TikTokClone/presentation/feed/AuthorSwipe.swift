import SwiftUI
import UIKit

extension View {
    // Balayage vers la gauche sur la vidéo affichée, comme TikTok : le profil de son auteur arrive de la droite sous le
    // doigt, la page recule un peu. Relâché au-delà d'un tiers (ou sur un balayage rapide), le profil s'ouvre pour de
    // bon dans la pile de navigation (`open`), avec les données déjà chargées ; sinon il repart. `author` nil : rien.
    func authorProfileSwipe(author: UserSummary?, container: AppContainer, open: @escaping (UserSummary) -> Void) -> some View {
        modifier(AuthorProfileSwipe(author: author, container: container, open: open))
    }
}

private struct AuthorProfileSwipe: ViewModifier {
    let author: UserSummary?
    let container: AppContainer
    let open: (UserSummary) -> Void
    @State private var progress: Double = 0
    @State private var width: CGFloat = 0
    // Profil montré pendant le balayage ; repris par la page poussée (`AppContainer.preparedProfile`).
    @State private var preview: (author: UserSummary, model: ProfileViewModel)?
    // Profil de l'auteur de la vidéo affichée, chargé d'avance (profil, relation, première page de la grille) : sur un
    // balayage rapide, il arrive complet au lieu de se remplir pendant la transition puis de se vider une fois poussé.
    @State private var prefetched: (username: String, model: ProfileViewModel)?

    // Temps passé sur une vidéo avant de charger le profil de son auteur (pas pendant un défilement rapide du feed).
    static let prefetchDelay = Duration.milliseconds(600)

    // Recul de la page pendant que le profil arrive (comme la navigation d'iOS).
    static let parallax = 0.3

    func body(content: Content) -> some View {
        content
            .offset(x: -progress * width * Self.parallax)
            .scrollDisabled(preview != nil)
            .overlay {
                if let preview {
                    ProfilePreview(author: preview.author, model: preview.model, container: container)
                        .offset(x: (1 - progress) * width)
                        .shadow(color: .black.opacity(0.25 * progress), radius: 12)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                AuthorSwipeGesture(
                    isEnabled: author != nil,
                    began: begin,
                    changed: { translation in progress = AuthorSwipe.progress(translation: translation, width: width) },
                    ended: end
                )
            )
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .onChange(of: progress > 0) { _, swiping in container.router.isSwipingToProfile = swiping }
            .task(id: author?.username) {
                guard let author, prefetched?.username != author.username else { return }
                try? await Task.sleep(for: Self.prefetchDelay)
                guard !Task.isCancelled else { return }
                let model = container.makeProfileViewModel(username: author.username)
                await model.load()
                guard !Task.isCancelled else { return }
                prefetched = (author.username, model)
                // Miniatures de la première page de la grille : affichées aussitôt pendant le balayage.
                await ThumbnailCache.shared.preload(model.grid(model.selectedGrid).items.prefix(12).map(\.thumbnailURL))
            }
    }

    private func begin() {
        guard let author else { return }
        let model = prefetched?.username == author.username ? prefetched?.model : nil
        preview = (author, model ?? container.makeProfileViewModel(username: author.username))
    }

    private func end(velocity: Double) {
        guard let preview else { return }
        if AuthorSwipe.completes(progress: progress, velocity: velocity) {
            withAnimation(.easeOut(duration: 0.2)) {
                progress = 1
            } completion: {
                // Page du profil poussée sans animation à la place de l'aperçu, avec son modèle déjà chargé.
                container.preparedProfile = preview.model
                prefetched = nil
                withoutAnimation {
                    open(preview.author)
                    progress = 0
                    self.preview = nil
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                progress = 0
            } completion: {
                self.preview = nil
            }
        }
    }
}

// Profil tel qu'il apparaîtra une fois ouvert : même écran, sous une barre ‹ et nom dessinée ici. Pas de
// `NavigationStack` : imbriquée dans celle de l'écran, elle empêchait ensuite ses liens de trouver leur destination
// (profil poussé vide, avatar inerte : bug rencontré).
private struct ProfilePreview: View {
    let author: UserSummary
    let model: ProfileViewModel
    let container: AppContainer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(model.profile?.displayName ?? author.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 60)
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 44)
            ProfileView(viewModel: model, container: container)
        }
        .foregroundStyle(.primary)
        .background(Color(.systemBackground).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}

// Glissement horizontal vers la gauche (UIKit) : ne démarre que si le doigt part vers la gauche plus qu'à la verticale,
// et laisse le défilement vertical du feed aux autres balayages.
private struct AuthorSwipeGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let began: () -> Void
    let changed: (Double) -> Void
    let ended: (_ velocity: Double) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.5
        }

        // Le défilement du feed (désactivé dès que le balayage commence), l'appui long, les touchers restent possibles.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = Double(recognizer.translation(in: recognizer.view).x)
        switch recognizer.state {
        case .began:
            began()
            changed(translation)
        case .changed:
            changed(translation)
        case .ended:
            ended(Double(recognizer.velocity(in: recognizer.view).x))
        case .cancelled, .failed:
            // Geste interrompu : le profil repart toujours.
            changed(0)
            ended(0)
        default:
            break
        }
    }
}
