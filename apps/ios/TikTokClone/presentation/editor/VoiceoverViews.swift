import AVFoundation
import SwiftUI

// Voix off et effets de voix, comme TikTok (ADR-064).

// Séance de l'écran « Voix off » : enregistrements posés à la tête de lecture, sans chevauchement, ⌫ retire le dernier,
// « Son d'origine ». « Terminé » les donne au plan en un seul pas d'annulation. La lecture est confiée à `playback`
// (vidéo jouée sans son pendant l'enregistrement, pour que le micro ne la reprenne pas).
@MainActor
@Observable
final class VoiceoverSession {
    private(set) var track: VoiceoverTrack
    var originalSound: Bool
    private(set) var recordingStart: Duration?
    var errorMessage: String?

    private let recorder: any VoiceRecorder
    private let currentTime: @MainActor () -> Duration
    private let playback: @MainActor (_ playing: Bool, _ muted: Bool) -> Void
    private var autoStop: Task<Void, Never>?

    init(
        clips: [VoiceoverClip], duration: Duration, originalSound: Bool, recorder: any VoiceRecorder,
        currentTime: @escaping @MainActor () -> Duration, playback: @escaping @MainActor (Bool, Bool) -> Void
    ) {
        track = VoiceoverTrack(clips: clips, duration: duration)
        self.originalSound = originalSound
        self.recorder = recorder
        self.currentTime = currentTime
        self.playback = playback
    }

    var isRecording: Bool { recordingStart != nil }
    var clips: [VoiceoverClip] { track.clips }

    // Enregistre à partir de la tête de lecture, jusqu'au carré, à la fin de la vidéo ou au début de la voix suivante.
    func startRecording() async {
        guard !isRecording else { return }
        let start = currentTime()
        guard let available = track.available(at: start) else {
            errorMessage = "Place la tête de lecture hors d'une voix off, avant la fin de la vidéo."
            return
        }
        guard await recorder.requestPermission() else {
            errorMessage = "Autorise le micro dans Réglages pour enregistrer une voix off."
            return
        }
        guard recorder.start() else {
            errorMessage = "Impossible d'enregistrer."
            return
        }
        recordingStart = start
        playback(true, true)
        autoStop = Task { [weak self] in
            try? await Task.sleep(for: available)
            guard !Task.isCancelled else { return }
            self?.stopRecording()
        }
    }

    func stopRecording() {
        guard let start = recordingStart else { return }
        autoStop?.cancel()
        recordingStart = nil
        playback(false, false)
        guard let (file, recorded) = recorder.stop() else { return }
        // Le micro démarre un peu avant la vidéo : le fichier dure plus que la lecture. Ce début est sauté, pour que la
        // voix tombe sur les images où elle a été dite et finisse à la tête de lecture (sinon l'enregistrement suivant,
        // lancé de là, serait refusé).
        let played = currentTime() - start
        let duration = played > .zero ? min(recorded, played) : recorded
        let clip = VoiceoverClip(id: UUID(), file: file, start: start, duration: duration, offset: recorded - duration)
        if !track.add(clip) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func removeLast() {
        guard !isRecording, let clip = track.removeLast() else { return }
        try? FileManager.default.removeItem(at: clip.file)
    }
}

// Écran « Voix off », comme TikTok : la vidéo (toucher = lecture), puis un panneau sombre : frise de la vidéo sous une
// tête de lecture fixe (glisser déplace la lecture, voix off en bleu-vert), micro rouge (carré pendant
// l'enregistrement), ⌫ retire le dernier enregistrement, « Son d'origine » et « Terminé ».
struct VoiceoverRecorderView: View {
    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    @State private var session: VoiceoverSession
    @State private var dragStart: Duration?
    @Environment(\.dismiss) private var dismiss

    private static let pointsPerSecond: CGFloat = 40

    init(model: VideoEditorViewModel, preview: EditorPreviewPlayer, recorder: any VoiceRecorder) {
        self.model = model
        self.preview = preview
        _session = State(
            initialValue: VoiceoverSession(
                clips: model.plan.voiceovers, duration: model.plan.outputDuration, originalSound: !model.plan.isMuted, recorder: recorder,
                currentTime: { preview.currentTime },
                playback: { playing, muted in
                    preview.player.isMuted = muted
                    if playing { preview.play() } else { preview.pause() }
                }))
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerLayerView(player: preview.player, fills: !preview.isSimplified)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .background(Color.black)
                .overlay {
                    if !preview.isPlaying && !session.isRecording {
                        Image(systemName: "play.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.85)).allowsHitTesting(false)
                    }
                }
                .onTapGesture { if !session.isRecording { preview.togglePlayback() } }
                .frame(maxHeight: .infinity)
                .padding(.top, 8)
            panel
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            preview.loops = false
            preview.pause()
        }
        .onDisappear {
            session.stopRecording()
            preview.player.isMuted = false
            preview.loops = true
        }
        .alert("Voix off", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var panel: some View {
        VStack(spacing: 22) {
            strip
                .frame(height: 96)
                .padding(.top, 28)
            ZStack {
                recordButton
                if !session.clips.isEmpty && !session.isRecording {
                    Button("Supprimer le dernier enregistrement", systemImage: "delete.left.fill") { session.removeLast() }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .offset(x: 110)
                        .accessibilityIdentifier("voiceover.removeLast")
                }
            }
            HStack {
                Button {
                    session.originalSound.toggle()
                } label: {
                    Label {
                        Text("Son d'origine")
                    } icon: {
                        Image(systemName: session.originalSound ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(session.originalSound ? Color.brandPink : .white)
                    }
                    .font(.title3)
                }
                .accessibilityAddTraits(session.originalSound ? .isSelected : [])
                .accessibilityIdentifier("voiceover.originalSound")
                Spacer()
                Button("Terminé") {
                    session.stopRecording()
                    model.setVoiceovers(session.clips, originalSound: session.originalSound)
                    dismiss()
                }
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("voiceover.done")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.11), in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
    }

    private var recordButton: some View {
        Button {
            if session.isRecording { session.stopRecording() } else { Task { await session.startRecording() } }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84)
                if session.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(Color.brandPink).frame(width: 30, height: 30)
                } else {
                    Circle().fill(Color.brandPink).frame(width: 70, height: 70)
                    Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.white)
                }
            }
        }
        .accessibilityLabel(session.isRecording ? "Arrêter l'enregistrement" : "Enregistrer une voix off")
        .accessibilityIdentifier("voiceover.record")
    }

    // Frise de toute la vidéo, défilée sous la tête de lecture fixe ; voix off posées en bleu-vert.
    private var strip: some View {
        GeometryReader { geometry in
            let total = CGFloat(model.plan.outputDuration.seconds) * Self.pointsPerSecond
            let offset = geometry.size.width / 2 - CGFloat(preview.currentTime.seconds) * Self.pointsPerSecond
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(model.plan.clips) { clip in
                        clipFrames(clip)
                    }
                }
                .frame(width: total, height: 56, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                ForEach(session.clips) { clip in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.1, green: 0.6, blue: 0.7).opacity(0.75))
                        .frame(width: CGFloat(clip.duration.seconds) * Self.pointsPerSecond, height: 56)
                        .offset(x: CGFloat(clip.start.seconds) * Self.pointsPerSecond)
                        .accessibilityLabel("Voix off")
                        .accessibilityIdentifier("voiceover.clip")
                }
                if let start = session.recordingStart {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.1, green: 0.6, blue: 0.7))
                        .frame(width: max(2, CGFloat((preview.currentTime - start).seconds) * Self.pointsPerSecond), height: 56)
                        .offset(x: CGFloat(start.seconds) * Self.pointsPerSecond)
                }
            }
            .offset(x: offset)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay {
                Rectangle().fill(.white).frame(width: 3, height: geometry.size.height).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { drag in
                        guard !session.isRecording else { return }
                        let origin = dragStart ?? preview.currentTime
                        dragStart = origin
                        preview.pause()
                        let seconds = origin.seconds - Double(drag.translation.width / Self.pointsPerSecond)
                        preview.seek(to: .seconds(min(max(seconds, 0), model.plan.outputDuration.seconds)))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .clipped()
        }
    }

    @ViewBuilder
    private func clipFrames(_ clip: EditClip) -> some View {
        let key = model.thumbnailKey(for: clip)
        let width = CGFloat(clip.outputDuration.seconds) * Self.pointsPerSecond
        HStack(spacing: 0) {
            if let images = model.thumbnails[key] {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image).resizable().scaledToFill().frame(width: width / CGFloat(max(images.count, 1)), height: 56).clipped()
                }
            } else {
                Color.white.opacity(0.12)
            }
        }
        .frame(width: width, height: 56)
        .task { await model.loadThumbnails(key) }
    }
}

// Effets de voix, comme TikTok : « Annuler » / « Enregistrer », la vidéo, sa progression, ⊘ et les onglets Tendances,
// Personnages, Améliorations, puis la grille des effets. Sans voix off, la grille est grisée et « Enregistrer » ouvre
// l'écran « Voix off » ; avec, « Voir l'enregistrement » le rouvre et 🔊 coupe ou remet le son d'origine. Un effet
// touché s'entend aussitôt ; « Annuler » remet l'effet d'avant.
struct VoiceEffectsView: View {
    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    let makeRecorder: () -> any VoiceRecorder
    @State private var category: VoiceEffect.Category = .trending
    @State private var initialEffect: VoiceEffect?
    @State private var isRecording = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Annuler") {
                    if let initialEffect, initialEffect != model.plan.voiceEffect { model.setVoiceEffect(initialEffect) }
                    dismiss()
                }
                .accessibilityIdentifier("voiceEffects.cancel")
                Spacer()
                Button("Enregistrer") { dismiss() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("voiceEffects.save")
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 52)
            PlayerLayerView(player: preview.player, fills: !preview.isSimplified)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .background(Color.black)
                .onTapGesture { preview.togglePlayback() }
                .frame(maxHeight: .infinity)
            progress
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            tabs
            Divider().overlay(.white.opacity(0.15))
            Text(hasVoice ? "Effet appliqué à ta voix off" : "Change ta voix ou enregistre une voix off")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(hasVoice ? 0.7 : 0.4))
                .padding(.vertical, 12)
            grid
                .frame(height: 210)
                .overlay {
                    if !hasVoice {
                        Text("Ajoute une voix off pour utiliser les effets de voix")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                }
            bottom
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear { if initialEffect == nil { initialEffect = model.plan.voiceEffect } }
        .fullScreenCover(isPresented: $isRecording) {
            VoiceoverRecorderView(model: model, preview: preview, recorder: makeRecorder())
        }
    }

    private var hasVoice: Bool { !model.plan.voiceovers.isEmpty }

    private var progress: some View {
        GeometryReader { geometry in
            let fraction = model.plan.outputDuration > .zero ? min(max(preview.currentTime / model.plan.outputDuration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 3)
                Capsule().fill(.white).frame(width: geometry.size.width * fraction, height: 3)
                Circle().fill(.white).frame(width: 14, height: 14).offset(x: geometry.size.width * fraction - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    preview.pause()
                    preview.seek(to: model.plan.outputDuration * Double(min(max(drag.location.x / geometry.size.width, 0), 1)))
                }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Lecture")
        .accessibilityValue(TimelineTime.label(preview.currentTime))
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            Button {
                model.setVoiceEffect(.none)
            } label: {
                Image(systemName: "nosign")
                    .font(.title2)
                    .foregroundStyle(model.plan.voiceEffect == .none ? Color.white : .white.opacity(0.6))
                    .frame(width: 56, height: 40)
            }
            .disabled(!hasVoice)
            .accessibilityLabel("Aucun effet de voix")
            .accessibilityIdentifier("voiceEffects.none")
            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 26)
            ForEach(VoiceEffect.Category.allCases) { option in
                Button {
                    category = option
                } label: {
                    VStack(spacing: 8) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(category == option ? Color.white : .white.opacity(0.55))
                        Capsule().fill(category == option ? Color.white : .clear).frame(height: 2)
                    }
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                }
                .accessibilityAddTraits(category == option ? .isSelected : [])
                .accessibilityIdentifier("voiceEffects.category.\(option.rawValue)")
            }
        }
        .padding(.trailing, 8)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 16) {
                ForEach(category.effects) { effect in
                    let selected = model.plan.voiceEffect == effect
                    Button {
                        model.setVoiceEffect(effect)
                    } label: {
                        VStack(spacing: 6) {
                            let colors = effect.colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
                            Image(systemName: effect.symbol)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.white : .clear, lineWidth: 2.5))
                            Text(effect.title)
                                .font(.caption.weight(selected ? .bold : .regular))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .accessibilityLabel(effect.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("voiceEffects.effect.\(effect.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
        .disabled(!hasVoice)
        .opacity(hasVoice ? 1 : 0.3)
    }

    @ViewBuilder
    private var bottom: some View {
        if hasVoice {
            HStack(spacing: 0) {
                Button {
                    isRecording = true
                } label: {
                    Label("Voir l'enregistrement", systemImage: "mic.fill").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("voiceEffects.showRecording")
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 26)
                Button(
                    model.plan.isMuted ? "Remettre le son d'origine" : "Couper le son d'origine",
                    systemImage: model.plan.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                ) {
                    model.toggleMuted()
                }
                .labelStyle(.iconOnly)
                .frame(width: 64)
                .accessibilityIdentifier("voiceEffects.originalSound")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(height: 54)
            .background(.white.opacity(0.18), in: Capsule())
        } else {
            Button {
                isRecording = true
            } label: {
                Label("Enregistrer", systemImage: "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.brandPink, in: Capsule())
            }
            .accessibilityIdentifier("voiceEffects.record")
        }
    }
}
