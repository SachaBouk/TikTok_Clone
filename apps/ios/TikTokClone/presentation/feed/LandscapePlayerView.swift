import AVFoundation
import Combine
import SwiftUI
import UIKit

// Plein écran d'une vidéo horizontale, comme TikTok : le même lecteur (pool du feed), en paysage, la vidéo entière.
// Un toucher affiche ou masque les commandes : ‹, description (« plus »), auteur, « … » (menu de la vidéo) ; pause au
// centre ; temps, barre de progression qu'on fait glisser ; j'aime, commentaires, favori et vitesse. Les commandes se
// masquent seules 3 s après pendant la lecture. Remettre l'iPhone droit referme le plein écran ; la vidéo boucle.
struct LandscapePlayerView: View {
    struct Actions {
        var togglePause: () -> Void
        var progress: () -> PlaybackProgress?
        var seek: (Double) -> Void
        var close: () -> Void
    }

    // Vidéo telle que chargée ; affichée avec les changements faits depuis (`VideoInteractionsModel.display`).
    let loadedVideo: FeedVideo
    let player: AVPlayer?
    let isPaused: Bool
    let actions: Actions
    let options: PlaybackOptionsModel
    let interactions: VideoInteractionsModel
    let container: AppContainer

    private var video: FeedVideo { interactions.display(loadedVideo) }

    // Délai avant que les commandes se masquent pendant la lecture.
    static let controlsDelay = Duration.seconds(3)

    @State private var controlsShown = true
    // Change à chaque toucher sur les commandes : relance le délai de masquage.
    @State private var activity = 0
    @State private var scrubbing = false
    @State private var expanded = false
    @State private var commentsVideo: FeedVideo?
    @State private var shareVideo: FeedVideo?
    @State private var reportedVideo: FeedVideo?
    @State private var menuVideo: FeedVideo?
    @State private var alertMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerLayerView(player: player, fills: false)
                .ignoresSafeArea()
                .accessibilityIdentifier("landscape.video")
            // Toucher la vidéo : commandes affichées ou masquées.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { setControls(!controlsShown) }
            if controlsShown {
                controls.transition(.opacity)
            }
            // Téléchargement lancé du menu (ADR-067) : sa progression, par-dessus le plein écran.
            VideoDownloadOverlay(model: container.downloads)
        }
        .animation(.easeInOut(duration: 0.2), value: controlsShown)
        .statusBarHidden(!controlsShown)
        .persistentSystemOverlays(.hidden)
        // Masquées seules pendant la lecture, après le délai ; jamais en pause ni pendant un glissement.
        .task(id: [activity, isPaused ? 1 : 0, scrubbing ? 1 : 0, controlsShown ? 1 : 0]) {
            guard controlsShown, !isPaused, !scrubbing else { return }
            try? await Task.sleep(for: Self.controlsDelay)
            if !Task.isCancelled { controlsShown = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if LandscapeRotation.leavesFullScreen(tilt: DeviceTilt(UIDevice.current.orientation)) { actions.close() }
        }
        // « Pas intéressé(e) » : la vidéo quitte le feed, le plein écran se referme.
        .onChange(of: interactions.notInterestedVideoIDs.contains(loadedVideo.id)) { _, removed in
            if removed { actions.close() }
        }
        .videoInteractionSheets(
            comments: $commentsVideo, share: $shareVideo, report: $reportedVideo, alert: $alertMessage, menu: $menuVideo,
            interactions: interactions, container: container
        )
        .environment(\.isLandscapePlayer, true)
        .preferredColorScheme(.dark)
    }

    private func react(_ kind: ReactionKind) {
        Task { if let message = await interactions.toggle(kind, on: loadedVideo) { alertMessage = message } }
    }

    private func setControls(_ shown: Bool) {
        controlsShown = shown
        activity += 1
    }

    // Toute action sur les commandes les garde affichées (délai relancé).
    private func touched(_ action: () -> Void) {
        action()
        activity += 1
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).frame(height: 130)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom).frame(height: 150)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .overlay {
            // Pause ou lecture au centre, dans un rond sombre.
            Button {
                touched(actions.togglePause)
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .frame(width: 72, height: 72)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(isPaused ? "Lecture" : "Pause")
            .accessibilityIdentifier("landscape.pause")
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: actions.close) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Quitter le plein écran")
            .accessibilityIdentifier("landscape.close")
            VStack(alignment: .leading, spacing: 10) {
                if let description = video.description, !description.isEmpty {
                    descriptionLine(description)
                }
                HStack(spacing: 8) {
                    AvatarView(url: video.author.avatarURL, name: video.author.displayName, size: 30)
                    Text(video.author.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 3)
                .padding(.trailing, 14)
                .padding(.vertical, 3)
                .background(.black.opacity(0.35), in: Capsule())
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 8)
            Spacer(minLength: 20)
            Button {
                touched { menuVideo = video }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Plus d’options")
            .accessibilityIdentifier("landscape.menu")
        }
        .buttonStyle(.plain)
    }

    // Une ligne avec « plus » ; touchée, la description entière (4 lignes au plus), retouchée, une ligne.
    private func descriptionLine(_ description: String) -> some View {
        Button {
            touched { expanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(description)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(expanded ? 4 : 1)
                    .multilineTextAlignment(.leading)
                if !expanded && description.count > 40 {
                    Text("plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("landscape.description")
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let progress = actions.progress()
                HStack(spacing: 6) {
                    Text(TimelineTime.label(progress?.position ?? .zero)).foregroundStyle(.white)
                    Text("/").foregroundStyle(.white.opacity(0.6))
                    Text(TimelineTime.label(progress?.duration ?? .zero)).foregroundStyle(.white.opacity(0.6))
                }
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            }
            .accessibilityIdentifier("landscape.time")
            PlaybackScrubber(
                progress: actions.progress, isPaused: isPaused, seek: actions.seek,
                onScrub: {
                    scrubbing = $0
                    activity += 1
                }
            )
            .accessibilityIdentifier("landscape.progress")
            HStack(spacing: 26) {
                counter(
                    video.viewer?.liked == true ? "heart.fill" : "heart", count: video.stats.likes,
                    tint: video.viewer?.liked == true ? Color(red: 1, green: 0.17, blue: 0.33) : .white, label: "J’aime",
                    identifier: "landscape.like"
                ) { react(.like) }
                counter("ellipsis.bubble.fill", count: video.stats.comments, tint: .white, label: "Commentaires", identifier: "landscape.comments") {
                    commentsVideo = video
                }
                counter(
                    "bookmark.fill", count: video.stats.favorites, tint: video.viewer?.favorited == true ? .yellow : .white,
                    label: "Favoris", identifier: "landscape.favorite"
                ) { react(.favorite) }
                Spacer(minLength: 0)
                Button {
                    touched { options.setSpeed(options.speed.next) }
                } label: {
                    Text(options.speed.shortLabel)
                        .font(.system(size: 18, weight: .bold))
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Vitesse \(options.speed.label)")
                .accessibilityIdentifier("landscape.speed")
            }
            .buttonStyle(.plain)
        }
    }

    private func counter(
        _ systemImage: String, count: Int, tint: Color, label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            touched(action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
                Text(count, format: .number.notation(.compactName)).font(.system(size: 16, weight: .semibold))
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(Text(count, format: .number))
        .accessibilityIdentifier(identifier)
    }
}

// Bouton « Plein écran » sous une vidéo horizontale, comme TikTok.
struct FullScreenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Plein écran", systemImage: "rectangle.portrait.rotate")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color(white: 0.2).opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("video.fullScreen")
    }
}

extension DeviceTilt {
    init(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .landscapeLeft, .landscapeRight: self = .landscape
        default: self = .other
        }
    }
}

extension View {
    // Plein écran en paysage d'une vidéo (feed, vidéo seule) : présenté sans animation, puis l'interface tourne ; à la
    // fermeture, elle revient en portrait d'abord, puis le plein écran disparaît (le feed ne passe jamais en paysage).
    func landscapePlayer<Content: View>(
        video: Binding<FeedVideo?>, @ViewBuilder content: @escaping (FeedVideo, _ close: @escaping () -> Void) -> Content
    ) -> some View {
        modifier(LandscapePlayerPresenter(video: video, content: content))
    }
}

private struct LandscapePlayerPresenter<Player: View>: ViewModifier {
    @Binding var video: FeedVideo?
    let content: (FeedVideo, @escaping () -> Void) -> Player
    @Environment(SessionStore.self) private var session
    // Connexion demandée pendant le plein écran (invité : j'aime, favori, commentaire, téléchargement…), refaite une
    // fois celui-ci retiré : sa feuille s'ouvrirait sinon depuis un écran caché, qui se refermerait mal. Message vide :
    // sans invitation.
    @State private var pendingSignIn: String?

    // Temps de la rotation vers le portrait avant de retirer le plein écran.
    static var rotationDelay: Duration { .milliseconds(400) }

    func body(content view: Content) -> some View {
        view.fullScreenCover(item: $video, onDismiss: requestPendingSignIn) { shown in
            content(shown, close)
                .onAppear {
                    OrientationLock.set(landscape: true)
                    session.signInInterceptor = { message in
                        pendingSignIn = message ?? ""
                        close()
                    }
                }
                .onDisappear { session.signInInterceptor = nil }
        }
    }

    private func requestPendingSignIn() {
        // Retiré avant de redemander (le plein écran a pu disparaître avant son `onDisappear`).
        session.signInInterceptor = nil
        guard let message = pendingSignIn else { return }
        pendingSignIn = nil
        session.requestSignIn(message: message.isEmpty ? nil : message)
    }

    private func close() {
        guard video != nil else { return }
        session.signInInterceptor = nil
        OrientationLock.set(landscape: false)
        Task {
            try? await Task.sleep(for: Self.rotationDelay)
            withoutAnimation { video = nil }
        }
    }
}

// Présentation et retrait du plein écran sans glissement : seule la rotation de l'interface se voit.
@MainActor
func withoutAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}
