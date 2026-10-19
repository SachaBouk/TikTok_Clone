import AVFoundation
import SwiftUI

// Caméra plein écran de la création, comme TikTok (ADR-052, ADR-062) : × et réglages à droite (caméra, lampe,
// minuteur), durée au-dessus du déclencheur (« 3 min », « 60 s », « 15 s ») ou « Vidéo | Photo » en mode Story,
// « Importer » (galerie) à droite du déclencheur, puis ✓ une fois des segments filmés, et modes « Caméra · Story · Live »
// en bas. En mode Live : titre et « Lancer le live » sur l'aperçu. Sans caméra (simulateur, refus), les modes et la
// galerie restent proposés.
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
    @Binding var mode: PublishDraftViewModel.Mode
    @Binding var liveTitle: String
    // Dernier média de la galerie, en miniature sur « Importer ».
    let importThumbnail: CGImage?
    let onFinish: (CameraOutcome) -> Void
    let onImport: () -> Void
    let onStartLive: () -> Void
    let onClose: () -> Void
    @State private var confirmingDiscard = false
    @FocusState private var isEditingTitle: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(
        model: CameraViewModel, preview: Preview, mode: Binding<PublishDraftViewModel.Mode>, liveTitle: Binding<String>,
        importThumbnail: CGImage?, onFinish: @escaping (CameraOutcome) -> Void, onImport: @escaping () -> Void,
        onStartLive: @escaping () -> Void, onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.preview = preview
        _mode = mode
        _liveTitle = liveTitle
        self.importThumbnail = importThumbnail
        self.onFinish = onFinish
        self.onImport = onImport
        self.onStartLive = onStartLive
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.status {
            case .starting:
                ProgressView().tint(.white)
            case .ready:
                preview.ignoresSafeArea()
            case .denied:
                unavailable(
                    title: "Caméra non autorisée", message: "Autorise l’accès à la caméra dans les Réglages pour filmer, ou importe une vidéo.",
                    showSettings: true)
            case .unavailable:
                unavailable(
                    title: "Caméra indisponible", message: "Cet appareil n’a pas de caméra. Importe une vidéo de ta galerie.", showSettings: false)
            }
            controls
            if let countdown = model.countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Enregistrement dans \(countdown) secondes")
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stop() } else if model.status == .ready { Task { await model.start() } }
        }
        .onChange(of: mode, initial: true) { _, mode in
            if mode != .live { model.setKind(mode == .story ? .story : .video) }
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
            if mode != .live, model.hasSegments || model.isRecording {
                TimelineView(.animation(paused: !model.isRecording)) { context in
                    SegmentProgressBar(model: model, date: context.date)
                }
                .frame(height: 5)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            HStack(alignment: .top) {
                closeButton
                Spacer()
                if mode == .live {
                    liveTitleField
                    Spacer()
                }
                settingsColumn
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            if !model.hasAudio, mode != .live, model.captureMode == .video, model.status == .ready {
                Label("Sans son : micro non autorisé", systemImage: "mic.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 12)
            }
            if mode == .live {
                liveButton
            } else {
                optionsRow
                shutterRow
            }
            modeTabs
        }
    }

    private var closeButton: some View {
        iconButton("xmark", label: "Fermer", enabled: !model.isRecording) {
            if model.hasSegments {
                confirmingDiscard = true
            } else {
                model.discard()
                onClose()
            }
        }
        // Attachée au bouton qui la déclenche (sinon popover dans un coin, iOS 26+).
        .confirmationDialog("Abandonner la vidéo ?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) {
                model.discard()
                onClose()
            }
        } message: {
            Text("Les segments filmés seront supprimés.")
        }
        .accessibilityIdentifier("camera.close")
    }

    // Réglages à droite : changer de caméra, lampe (caméra arrière), minuteur (vidéo).
    private var settingsColumn: some View {
        VStack(spacing: 22) {
            iconButton("arrow.triangle.2.circlepath", label: "Changer de caméra", enabled: model.canSwitchCamera) {
                Task { await model.switchCamera() }
            }
            if mode != .live {
                if model.canUseTorch {
                    iconButton(
                        model.torchOn ? "bolt.fill" : "bolt.slash.fill", label: model.torchOn ? "Éteindre la lampe" : "Allumer la lampe",
                        enabled: true
                    ) {
                        model.toggleTorch()
                    }
                }
                if model.captureMode == .video {
                    iconButton(
                        "timer", label: model.timerEnabled ? "Minuteur de 3 secondes activé" : "Minuteur de 3 secondes", enabled: !model.isBusy
                    ) {
                        model.timerEnabled.toggle()
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if model.timerEnabled {
                            Text("3s")
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .background(.white, in: Capsule())
                                .offset(x: 4, y: 2)
                        }
                    }
                }
            }
        }
    }

    // Au-dessus du déclencheur : durée de la vidéo, ou « Vidéo | Photo » en mode Story.
    @ViewBuilder
    private var optionsRow: some View {
        HStack(spacing: 22) {
            if mode == .story {
                ForEach(model.captureModes) { option in
                    optionButton(option.title, selected: model.captureMode == option) { model.captureMode = option }
                }
            } else {
                ForEach(RecordingLimit.allCases) { limit in
                    optionButton(limit.title, selected: model.limit == limit) { model.setLimit(limit) }
                }
            }
        }
        .disabled(!model.canChangeSettings)
        .opacity(model.canChangeSettings ? 1 : 0)
        .padding(.bottom, 18)
        .accessibilityIdentifier("camera.options")
    }

    private func optionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.white.opacity(0.2) : .clear, in: Capsule())
                .shadow(radius: 2)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var shutterRow: some View {
        HStack {
            Group {
                if model.captureMode == .video, model.hasSegments {
                    iconButton("delete.left", label: "Retirer le dernier segment", enabled: model.canRemoveLast) { model.removeLastSegment() }
                } else {
                    Color.clear
                }
            }
            .frame(width: 72, height: 72)
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
                            .frame(width: 48, height: 48)
                            .background(Color.brandPink, in: Circle())
                    }
                    .disabled(!model.canFinish)
                    .accessibilityLabel("Suivant")
                    .accessibilityIdentifier("camera.next")
                } else {
                    importButton
                }
            }
            .frame(width: 72, height: 72)
        }
        .padding(.horizontal, 28)
    }

    // « Importer » : galerie maison (ADR-062), avec le dernier média en miniature.
    private var importButton: some View {
        Button(action: onImport) {
            VStack(spacing: 4) {
                Group {
                    if let importThumbnail {
                        Image(decorative: importThumbnail, scale: 1).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.2).overlay(Image(systemName: "photo.on.rectangle").foregroundStyle(.white))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                Text("Importer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .disabled(model.isBusy)
        .accessibilityIdentifier("camera.import")
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
                Circle().stroke(.white.opacity(0.9), lineWidth: 6).frame(width: 84, height: 84)
                if model.captureMode == .photo {
                    Circle().fill(.white).frame(width: 68, height: 68)
                } else if model.isRecording {
                    RoundedRectangle(cornerRadius: 8).fill(Color.brandPink).frame(width: 34, height: 34)
                } else {
                    Circle().fill(Color.brandPink).frame(width: 68, height: 68)
                }
            }
        }
        .disabled(model.captureMode == .video ? !(model.canRecord || model.isRecording || model.countdown != nil) : model.isBusy)
        .opacity(model.status == .ready ? 1 : 0.4)
        .accessibilityLabel(shutterLabel)
        .accessibilityIdentifier("camera.shutter")
    }

    private var shutterLabel: String {
        if model.captureMode == .photo { return "Prendre la photo" }
        if model.isRecording { return "Arrêter l’enregistrement" }
        if model.countdown != nil { return "Annuler le minuteur" }
        return model.recording.isFull ? "Durée maximale atteinte" : "Filmer"
    }

    // Mode Live (ADR-053) : titre facultatif.
    private var liveTitleField: some View {
        TextField("Ajoute un titre", text: $liveTitle, axis: .vertical)
            .lineLimit(1...2)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .focused($isEditingTitle)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 220)
            .submitLabel(.done)
            .accessibilityIdentifier("publish.live.title")
    }

    private var liveButton: some View {
        VStack(spacing: 8) {
            if LiveRules.maxTitleLength - liveTitle.count < 20 {
                Text("\(LiveRules.maxTitleLength - liveTitle.count) caractères restants")
                    .font(.caption)
                    .foregroundStyle(liveTitle.count > LiveRules.maxTitleLength ? .red : .white.opacity(0.8))
            }
            Button {
                isEditingTitle = false
                model.stop()
                onStartLive()
            } label: {
                Text("Lancer le live")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(liveTitle.count > LiveRules.maxTitleLength)
            .accessibilityIdentifier("publish.live.start")
            Text("Tes abonnés sont prévenus. 2 heures au plus, rien n’est enregistré.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // « Caméra · Story · Live », point sous le mode choisi ; figés une fois des segments filmés.
    private var modeTabs: some View {
        HStack(spacing: 28) {
            ForEach(PublishDraftViewModel.Mode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    VStack(spacing: 6) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(mode == option ? .white : .white.opacity(0.55))
                        Circle().fill(mode == option ? .white : .clear).frame(width: 5, height: 5)
                    }
                }
                .disabled(!model.canChangeSettings)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
                .accessibilityIdentifier("publish.mode.\(option.rawValue)")
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .shadow(radius: 2)
        .accessibilityIdentifier("publish.mode")
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
        VStack(spacing: 12) {
            Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Ouvrir les Réglages") { openURL(url) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandPink)
            }
        }
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera.unavailable")
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
                Capsule().fill(Color.brandPink).frame(width: width * model.progress(at: date))
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
