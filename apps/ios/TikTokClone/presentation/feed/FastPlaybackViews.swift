import SwiftUI
import UIKit

// Appui long sur un côté de la vidéo (`FastPlayback`) : reconnaisseur d'UIKit plutôt qu'un geste SwiftUI. Une fois
// reconnu, il empêche le défilement de la page (deux reconnaisseurs d'UIKit ne réussissent pas ensemble) : le doigt peut
// alors glisser vers le bas pour verrouiller ; inversement, une page qui défile avant la fin du délai l'annule. Il annule
// aussi le toucher (pause) de la page. Un appui long au milieu est ignoré (réservé).
struct FastPlaybackGesture: UIGestureRecognizerRepresentable {
    let model: FastPlaybackModel
    // Largeur de la page, pour savoir si l'appui est sur un côté.
    let width: CGFloat
    let bottomInset: CGFloat
    let isEnabled: Bool

    // Délai de l'appui long.
    static let minimumDuration: TimeInterval = 0.35

    final class Coordinator {
        // Position du doigt au début de l'appui ; nil : appui au milieu, ignoré.
        var startY: CGFloat?
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = Self.minimumDuration
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            guard FastPlayback.isSide(x: location.x, width: width) else {
                coordinator.startY = nil
                return
            }
            coordinator.startY = location.y
            model.begin(bottomInset: bottomInset)
        case .changed:
            guard let startY = coordinator.startY else { return }
            model.drag(translation: location.y - startY)
        case .ended:
            guard coordinator.startY != nil else { return }
            coordinator.startY = nil
            model.end()
        case .cancelled, .failed:
            guard coordinator.startY != nil else { return }
            coordinator.startY = nil
            model.cancel()
        default:
            break
        }
    }
}

// Bandeau du bas pendant l'appui, comme TikTok : sombre avec deux flèches vers le bas (« Glisse en bas… »), puis blanc
// avec un cadenas une fois le doigt descendu (« Relâche… »).
struct FastPlaybackHintPill: View {
    let hint: FastPlayback.Hint

    var body: some View {
        HStack(spacing: 10) {
            if hint.isArmed {
                Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold))
            } else {
                DownTriangles()
            }
            Text(hint.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(hint.isArmed ? Color.black : Color.white)
        .padding(.horizontal, 24)
        .frame(height: 38)
        .background(hint.isArmed ? Color.white : Color(white: 0.2), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("video.fastHint")
    }

    // Deux petits triangles pointés vers le bas, le second plus pâle.
    private struct DownTriangles: View {
        var body: some View {
            VStack(spacing: 1.5) {
                Triangle().fill(.white).frame(width: 11, height: 7)
                Triangle().fill(.white.opacity(0.55)).frame(width: 11, height: 7)
            }
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

// Bas de l'écran pendant l'appui : ce qui est sous la vidéo (barre d'onglets) est recouvert de noir, avec le bandeau au
// milieu ; sans barre dessous (vidéo seule), le bandeau est posé sur la vidéo. Placé au-dessus de la barre d'onglets
// (`MainTabView`) et de la vidéo seule.
struct FastPlaybackBottomBar: View {
    let model: FastPlaybackModel

    var body: some View {
        GeometryReader { geometry in
            let safeBottom = geometry.safeAreaInsets.bottom
            let band = model.bottomInset
            let hasBand = band > safeBottom + Self.pillHeight
            ZStack(alignment: .bottom) {
                if let hint = model.state.hint {
                    if hasBand {
                        Color.black.frame(height: band)
                    }
                    FastPlaybackHintPill(hint: hint)
                        .padding(.bottom, hasBand ? safeBottom + (band - safeBottom - Self.pillHeight) / 2 : safeBottom + 28)
                        .sensoryFeedback(.impact(weight: .light), trigger: hint.isArmed) { _, armed in armed }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
    }

    private static let pillHeight: CGFloat = 38
}

// Message du haut après un changement de verrouillage : « Verrouillée à la vitesse accélérée ×2 » (cadenas fermé) ou
// « Retour à la vitesse normale » (cadenas ouvert), sur une plaque grise translucide.
struct FastPlaybackNoticeView: View {
    let model: FastPlaybackModel

    var body: some View {
        ZStack {
            if let notice = model.notice {
                HStack(spacing: 12) {
                    Image(systemName: notice.systemImage).font(.system(size: 18, weight: .semibold))
                    Text(notice.text)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(Color(white: 0.35, opacity: 0.8), in: RoundedRectangle(cornerRadius: 14))
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("video.fastNotice")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .allowsHitTesting(false)
    }
}
