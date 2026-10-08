import AVFoundation
import SwiftUI

// Visionneuse plein écran des stories (ADR-051) : barre de progression par story, auteur et date en haut ; en bas, la
// réponse par message et le cœur (story d'un autre), ou le nombre de vues et la suppression (sa story).
// Toucher à droite : suivante ; à gauche : précédente ; appui long : pause ; glisser vers le bas : fermer.
struct StoryViewerView: View {
    @State private var model: StoryViewerModel
    let container: AppContainer
    @State private var player = StoryPlayerController()
    @State private var replyText = ""
    @State private var isSending = false
    @FocusState private var isReplying: Bool
    @State private var reporting: ReportTarget?
    @State private var viewersStory: Story?
    @State private var isConfirmingDelete = false
    @State private var pressStart: Date?
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(model: StoryViewerModel, container: AppContainer) {
        _model = State(initialValue: model)
        self.container = container
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                media
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(pressGesture(width: geometry.size.width))
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    footer
                }
                if let notice = model.notice {
                    Text(notice)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(2))
                            if model.notice == notice { model.notice = nil }
                        }
                        .accessibilityIdentifier("story.notice")
                }
            }
            .offset(y: dragOffset)
            .opacity(1 - min(0.5, dragOffset / 600))
        }
        .foregroundStyle(.white)
        .statusBarHidden()
        .task { await model.start() }
        // Média de la story courante : vidéo chargée et lue, ou horloge des photos.
        .task(id: model.current?.id) {
            guard let story = model.current else { return }
            if story.mediaType == .video {
                player.onProgress = { model.videoProgress($0) }
                player.onEnd = { model.videoEnded() }
                player.load(story.mediaURL)
                if !model.isPaused { player.play() }
            } else {
                player.stop()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                model.tick(.milliseconds(50))
            }
        }
        .onChange(of: model.isPaused) { _, paused in
            if paused { player.pause() } else if model.current?.mediaType == .video { player.play() }
        }
        .onChange(of: model.state) { _, state in
            if state == .finished { dismiss() }
        }
        .onChange(of: isReplying) { _, replying in
            if replying { model.pause(.replying) } else { model.resume(.replying) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.resume(.background) } else { model.pause(.background) }
        }
        .onDisappear { player.stop() }
        .sheet(item: $viewersStory, onDismiss: { model.resume(.sheet) }) { story in
            StoryViewersView(story: story, list: container.makeStoryViewersList(storyID: story.id))
                .presentationDetents([.medium, .large])
        }
        .reportSheet($reporting, container: container, onDismiss: { model.resume(.sheet) })
    }

    // ─── Média ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private var media: some View {
        switch model.state {
        case .loading:
            ProgressView().tint(.white)
        case .failed(let message):
            ContentUnavailableView {
                Label("Stories indisponibles", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await model.retry() } }
                Button("Fermer") { model.close() }
            }
        case .showing, .finished:
            if let story = model.current {
                // En overlay : recadrée, l'image ne doit pas agrandir l'écran (même piège que le feed).
                Color.black
                    .overlay {
                        AsyncImage(url: story.mediaType == .photo ? story.mediaURL : story.thumbnailURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(.white)
                        }
                    }
                    .overlay {
                        if story.mediaType == .video { PlayerLayerView(player: player.player) }
                    }
                    .clipped()
                    .accessibilityElement()
                    .accessibilityLabel(story.mediaType == .photo ? "Story photo" : "Story vidéo")
                    .accessibilityIdentifier("story.media")
            }
        }
    }

    // Un seul geste pour tout le média : toucher bref à gauche ou à droite, appui long (pause), glisser vers le bas.
    private func pressGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = .now
                    model.pause(.holding)
                }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let held = Date.now.timeIntervalSince(pressStart ?? .now)
                pressStart = nil
                model.resume(.holding)
                if value.translation.height > 120 {
                    model.close()
                    return
                }
                withAnimation(.snappy) { dragOffset = 0 }
                guard held < 0.3, abs(value.translation.width) < 20, abs(value.translation.height) < 20 else { return }
                if isReplying {
                    isReplying = false
                } else if value.location.x < width / 3 {
                    model.previous()
                } else {
                    model.next()
                }
            }
    }

    // ─── En-tête ─────────────────────────────────────────────────────────────

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(model.stories.enumerated()), id: \.element.id) { index, _ in
                    StoryProgressBar(
                        fraction: index < model.position.story ? 1 : index == model.position.story ? model.progress : 0)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                if let story = model.current {
                    AvatarView(url: story.author.avatarURL, name: story.author.displayName, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.isOwn ? "Ta story" : story.author.displayName).font(.subheadline.bold())
                        Text.relative(story.publishedAt).font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer()
                Button("Fermer", systemImage: "xmark") { model.close() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("story.close")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.5), radius: 3)
    }

    // ─── Pied ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var footer: some View {
        if let story = model.current, model.state == .showing {
            Group {
                if model.isOwn { ownFooter(story) } else { replyFooter(story) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 24)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    // Sa story : nombre de vues (liste des personnes), suppression confirmée à côté du bouton.
    private func ownFooter(_ story: Story) -> some View {
        HStack {
            Button {
                model.pause(.sheet)
                viewersStory = story
            } label: {
                Label("\(story.stats?.viewers ?? 0) vue\((story.stats?.viewers ?? 0) > 1 ? "s" : "")", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("story.viewers")
            Spacer()
            Menu {
                Button("Supprimer la story", systemImage: "trash", role: .destructive) {
                    model.pause(.sheet)
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis").font(.title3.weight(.bold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Gérer la story")
            .accessibilityIdentifier("story.manage")
            .confirmationDialog("Supprimer cette story ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { Task { await model.deleteCurrent() } }
            } message: {
                Text("Ses vues et ses likes disparaîtront aussi.")
            }
            .onChange(of: isConfirmingDelete) { _, confirming in
                if !confirming { model.resume(.sheet) }
            }
        }
    }

    // Story d'un autre : réponse par message, cœur, signalement.
    private func replyFooter(_ story: Story) -> some View {
        HStack(spacing: 12) {
            TextField("", text: $replyText, prompt: Text("Envoyer un message…").foregroundStyle(.white.opacity(0.7)))
                .focused($isReplying)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
                .disabled(isSending)
                .accessibilityIdentifier("story.reply")
            if isReplying {
                Button("Envoyer", systemImage: "paperplane.fill") { send() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .accessibilityIdentifier("story.send")
            } else {
                Button(story.liked ? "Je n’aime plus" : "J’aime", systemImage: story.liked ? "heart.fill" : "heart") {
                    model.toggleLike()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(story.liked ? .red : .white)
                .accessibilityIdentifier("story.like")
                Menu {
                    Button("Signaler", systemImage: "flag", role: .destructive) {
                        guard container.session.profile != nil else { return container.session.requestSignIn() }
                        model.pause(.sheet)
                        reporting = .story(id: story.id)
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.title3.weight(.bold)).frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Plus d’options")
                .accessibilityIdentifier("story.more")
            }
        }
    }

    private func send() {
        let text = replyText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else { return }
        isSending = true
        Task {
            if await model.sendReply(text) {
                replyText = ""
                isReplying = false
            }
            isSending = false
        }
    }
}

// Segment de la barre de progression.
private struct StoryProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.white.opacity(0.35))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
        }
    }
}

// Lecteur d'une story vidéo : un AVPlayer, sa progression et sa fin, pour la visionneuse.
@MainActor
@Observable
final class StoryPlayerController {
    let player = AVPlayer()
    var onProgress: ((Double) -> Void)?
    var onEnd: (() -> Void)?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    func load(_ url: URL) {
        removeObservers()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let duration = self.player.currentItem?.duration, duration.isNumeric, duration.seconds > 0 else { return }
                self.onProgress?(time.seconds / duration.seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.onEnd?() }
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
    }

    private func removeObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }
}
