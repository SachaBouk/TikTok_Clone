import AVFoundation
import SwiftUI

// Caméra plein écran (ADR-052) : aperçu, réglages à droite (caméra, lampe, minuteur), barre de progression des segments,
// déclencheur ; « Suivant » passe les segments à l'éditeur. En mode Story, sélecteur « Vidéo | Photo ».
// Ce que la caméra rend : des segments filmés (vers l'éditeur), ou une photo de story.
enum CameraOutcome {
    case segments([SourceClip])
    case photo(Data)
}

// Caméra ouverte : son modèle et la session de capture de son aperçu, créés ensemble à l'ouverture.
struct CameraSetup: Identifiable {
    let id = UUID()
    let model: CameraViewModel
    let session: AVCaptureSession
}

struct CameraView<Preview: View>: View {
    @State private var model: CameraViewModel
    let preview: Preview
    let onFinish: (CameraOutcome) -> Void
    let onCancel: () -> Void
    @State private var confirmingDiscard = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(model: CameraViewModel, preview: Preview, onFinish: @escaping (CameraOutcome) -> Void, onCancel: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.preview = preview
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.status {
            case .starting:
                ProgressView().tint(.white)
            case .ready:
                preview.ignoresSafeArea()
                controls
            case .denied:
                unavailable(
                    title: "Caméra non autorisée",
                    message: "Autorise l’accès à la caméra dans les Réglages pour filmer, ou choisis une vidéo dans la galerie.",
                    showSettings: true)
            case .unavailable:
                unavailable(
                    title: "Caméra indisponible", message: "Cet appareil n’a pas de caméra. Choisis une vidéo dans la galerie.", showSettings: false)
            }
            if let countdown = model.countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Enregistrement dans \(countdown) secondes")
            }
        }
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stop() } else if model.status == .ready { Task { await model.start() } }
        }
        .alert(
            "Caméra",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                closeButton
                Spacer()
                VStack(spacing: 18) {
                    iconButton("arrow.triangle.2.circlepath.camera", label: "Changer de caméra", enabled: model.canSwitchCamera) {
                        Task { await model.switchCamera() }
                    }
                    if model.canUseTorch {
                        iconButton(
                            model.torchOn ? "bolt.fill" : "bolt.slash", label: model.torchOn ? "Éteindre la lampe" : "Allumer la lampe", enabled: true
                        ) {
                            model.toggleTorch()
                        }
                    }
                    if model.captureMode == .video {
                        iconButton(
                            model.timerEnabled ? "timer.circle.fill" : "timer",
                            label: model.timerEnabled ? "Minuteur activé" : "Minuteur de 3 secondes",
                            enabled: !model.isBusy
                        ) {
                            model.timerEnabled.toggle()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            if !model.hasAudio, model.captureMode == .video {
                Label("Sans son : micro non autorisé", systemImage: "mic.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 12)
            }
            bottomBar
        }
    }

    private var closeButton: some View {
        iconButton("xmark", label: "Fermer", enabled: !model.isRecording) {
            if model.hasSegments {
                confirmingDiscard = true
            } else {
                model.discard()
                onCancel()
            }
        }
        // Attachée au bouton qui la déclenche (sinon popover dans un coin, iOS 26+).
        .confirmationDialog("Abandonner la vidéo ?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) {
                model.discard()
                onCancel()
            }
        } message: {
            Text("Les segments filmés seront supprimés.")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if model.captureMode == .video {
                TimelineView(.animation(paused: !model.isRecording)) { context in
                    SegmentProgressBar(model: model, date: context.date)
                }
                .frame(height: 6)
                .padding(.horizontal, 16)
            }
            HStack {
                Group {
                    if model.captureMode == .video, model.hasSegments {
                        iconButton("delete.left", label: "Retirer le dernier segment", enabled: model.canRemoveLast) { model.removeLastSegment() }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 64, height: 64)
                Spacer()
                shutter
                Spacer()
                Group {
                    if model.captureMode == .video, model.hasSegments {
                        Button {
                            if let segments = model.finishRecording() { onFinish(.segments(segments)) }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.red, in: Circle())
                        }
                        .disabled(!model.canFinish)
                        .accessibilityLabel("Suivant")
                        .accessibilityIdentifier("camera.next")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 64, height: 64)
            }
            .padding(.horizontal, 24)
            if model.captureModes.count > 1 {
                Picker("Mode", selection: $model.captureMode) {
                    ForEach(model.captureModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(model.isBusy || model.hasSegments)
            }
        }
        .padding(.bottom, 16)
    }

    private var shutter: some View {
        Button {
            if model.captureMode == .photo {
                Task {
                    if let data = await model.takePhoto() {
                        model.stop()
                        onFinish(.photo(data))
                    }
                }
            } else {
                model.shutterTapped()
            }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 5).frame(width: 80, height: 80)
                if model.captureMode == .photo {
                    Circle().fill(.white).frame(width: 66, height: 66)
                } else if model.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 32, height: 32)
                } else {
                    Circle().fill(.red).frame(width: 66, height: 66)
                }
            }
        }
        .disabled(model.captureMode == .video ? !(model.canRecord || model.isRecording || model.countdown != nil) : model.isBusy)
        .accessibilityLabel(shutterLabel)
        .accessibilityIdentifier("camera.shutter")
    }

    private var shutterLabel: String {
        if model.captureMode == .photo { return "Prendre la photo" }
        if model.isRecording { return "Arrêter l’enregistrement" }
        if model.countdown != nil { return "Annuler le minuteur" }
        return model.recording.isFull ? "Durée maximale atteinte" : "Filmer"
    }

    private func iconButton(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .shadow(radius: 3)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func unavailable(title: String, message: String, showSettings: Bool) -> some View {
        VStack {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, 16)
            Spacer()
            ContentUnavailableView {
                Label(title, systemImage: "camera")
            } description: {
                Text(message)
            } actions: {
                if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Ouvrir les Réglages") { openURL(url) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Choisir dans la galerie") { onCancel() }
            }
            .foregroundStyle(.white)
            Spacer()
        }
        .environment(\.colorScheme, .dark)
    }
}

// Barre des segments : un trait par segment filmé, le segment en cours qui avance, la limite au bout.
private struct SegmentProgressBar: View {
    let model: CameraViewModel
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.red).frame(width: width * model.progress(at: date))
                // Séparations entre segments.
                ForEach(Array(model.recording.segments.indices), id: \.self) { index in
                    let end = model.recording.segments[...index].reduce(Duration.zero) { $0 + $1.duration }
                    Rectangle().fill(.white).frame(width: 2).offset(x: width * min(1, end / model.recording.maxDuration) - 1)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Durée filmée")
        .accessibilityValue(Text(model.progress(at: date), format: .percent.precision(.fractionLength(0))))
    }
}

// Aperçu de la caméra (couche `AVCaptureVideoPreviewLayer`), plein écran, en portrait.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
