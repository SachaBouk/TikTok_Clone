import SwiftUI
import UIKit

// Appui long sur un côté de la vidéo (`FastPlayback`) : reconnaisseur d'UIKit plutôt qu'un geste SwiftUI. Une fois
// reconnu, il empêche le défilement de la page (deux reconnaisseurs d'UIKit ne réussissent pas ensemble) : le doigt peut
// alors glisser vers le bas pour verrouiller ; inversement, une page qui défile avant la fin du délai l'annule. Il annule
// aussi le toucher (pause) de la page. Un appui long au milieu ouvre le menu de la vidéo (ADR-067).
struct FastPlaybackGesture: UIGestureRecognizerRepresentable {
    let model: PlaybackOptionsModel
    // Largeur de la page, pour savoir si l'appui est sur un côté.
    let width: CGFloat
    let bottomInset: CGFloat
    let isEnabled: Bool
    // Faux en pause : l'appui long sur un côté ne fait rien, le menu reste possible.
    let allowsFast: Bool
    // Appui long au milieu : menu de la vidéo.
    let openMenu: () -> Void

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
            let isSide = FastPlayback.isSide(x: location.x, width: width)
            guard isSide, allowsFast else {
                coordinator.startY = nil
                if !isSide { openMenu() }
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
    let model: PlaybackOptionsModel

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

// Message du haut : « Verrouillée à la vitesse accélérée ×2 » (cadenas fermé), « Retour à la vitesse normale » (cadenas
// ouvert), ou celui du défilement automatique (ADR-067), sur une plaque grise translucide. Quand le défilement automatique
// vient d'être activé, un bouton rond à droite le coupe.
struct FastPlaybackNoticeView: View {
    let model: PlaybackOptionsModel

    var body: some View {
        ZStack {
            if let notice = model.notice {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        if let systemImage = notice.systemImage {
                            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                        }
                        Text(notice.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(Color(white: 0.35, opacity: 0.8), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("video.fastNotice")
                    .allowsHitTesting(false)
                    if notice == .autoScrollOn {
                        Button {
                            model.setAutoScroll(false)
                        } label: {
                            AutoScrollIcon(crossed: true)
                                .frame(width: 40, height: 40)
                                .background(Color(white: 0.25, opacity: 0.85), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Désactiver le défilement automatique")
                        .accessibilityIdentifier("video.autoScrollOff")
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
    }
}

// Icône du défilement automatique, comme TikTok : une flèche vers le haut au-dessus de deux traits ; barrée sur le bouton
// qui le coupe.
struct AutoScrollIcon: View {
    var crossed = false
    var color: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrowshape.up").font(.system(size: 15, weight: .semibold))
            Capsule().frame(width: 10, height: 1.8)
            Capsule().frame(width: 10, height: 1.8)
        }
        .foregroundStyle(color)
        .overlay {
            if crossed {
                Capsule().fill(color).frame(width: 2.2, height: 26).rotationEffect(.degrees(-45))
            }
        }
        .accessibilityHidden(true)
    }
}

// Bas de la vidéo en affichage allégé (ADR-067), comme TikTok : sur fond noir, barre de progression qu'on fait glisser,
// puis × (sortir) à gauche et une pastille pause / lecture et vitesse à droite (un toucher passe à la vitesse suivante).
struct ClearModeBar: View {
    let progress: () -> PlaybackProgress?
    let isPaused: Bool
    let speed: PlaybackSpeed
    let bottomInset: CGFloat
    let seek: (Double) -> Void
    let togglePause: () -> Void
    let cycleSpeed: () -> Void
    let close: () -> Void

    private static let control = Color(white: 0.16)

    var body: some View {
        VStack(spacing: 14) {
            scrubber
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Self.control, in: Circle())
                }
                .accessibilityLabel("Quitter l’affichage allégé")
                .accessibilityIdentifier("clearMode.close")
                Spacer()
                HStack(spacing: 0) {
                    Button(action: togglePause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 60, height: 44)
                    }
                    .accessibilityLabel(isPaused ? "Lecture" : "Pause")
                    .accessibilityIdentifier("clearMode.pause")
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 20)
                    Button(action: cycleSpeed) {
                        Text(speed.shortLabel)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 60, height: 44)
                    }
                    .accessibilityLabel("Vitesse \(speed.label)")
                    .accessibilityIdentifier("clearMode.speed")
                }
                .background(Self.control, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, bottomInset + 6)
        .background(.black)
    }

    private var scrubber: some View {
        PlaybackScrubber(progress: progress, isPaused: isPaused, seek: seek)
            .accessibilityIdentifier("clearMode.progress")
    }
}

// Barre de progression qu'on fait glisser (affichage allégé, lecteur plein écran) : fine ligne, point à la position,
// plus gros sous le doigt ; relue à chaque image, figée en pause.
struct PlaybackScrubber: View {
    let progress: () -> PlaybackProgress?
    let isPaused: Bool
    let seek: (Double) -> Void
    // Début et fin d'un glissement (le lecteur plein écran garde alors ses commandes affichées).
    var onScrub: (Bool) -> Void = { _ in }
    // Position tenue sous le doigt pendant le glissement.
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.animation(paused: isPaused || dragFraction != nil)) { _ in
            let fraction = dragFraction ?? progress()?.fraction ?? 0
            GeometryReader { geometry in
                let x = geometry.size.width * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 2)
                    Capsule().fill(.white.opacity(0.85)).frame(width: x, height: 2)
                    Circle().fill(.white).frame(width: dragFraction == nil ? 7 : 12, height: dragFraction == nil ? 7 : 12)
                        .offset(x: min(max(0, x - 4), geometry.size.width - 8))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragFraction == nil { onScrub(true) }
                            let fraction = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                            dragFraction = fraction
                            seek(fraction)
                        }
                        .onEnded { _ in
                            dragFraction = nil
                            onScrub(false)
                        }
                )
            }
            .frame(height: 22)
        }
        .accessibilityElement()
        .accessibilityLabel("Progression de la vidéo")
    }
}

// Téléchargement d'une vidéo (ADR-067) : progression au centre de l'écran, puis « Enregistrée dans Photos » ou l'erreur.
struct VideoDownloadOverlay: View {
    let model: VideoDownloadModel

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                EmptyView()
            case .downloading(let fraction):
                VStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                        Circle().trim(from: 0, to: max(0.02, fraction)).stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: fraction)
                        Text("\(Int(fraction * 100)) %").font(.caption.weight(.semibold))
                    }
                    .frame(width: 52, height: 52)
                    Text("Enregistrement…").font(.subheadline.weight(.semibold))
                }
                .frame(width: 160, height: 130)
                .background(Color(white: 0.12, opacity: 0.85), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("download.progress")
            case .saved:
                message("Enregistrée dans Photos", systemImage: "checkmark.circle.fill")
            case .failed(let text):
                message(text, systemImage: "exclamationmark.circle.fill")
            }
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.2), value: model.state == .idle)
        .allowsHitTesting(false)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(white: 0.12, opacity: 0.85), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 40)
            .transition(.opacity)
            .accessibilityIdentifier("download.message")
    }
}
