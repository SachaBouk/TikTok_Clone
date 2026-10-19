import SwiftUI

// Éditeur par clips, comme TikTok (ADR-062) : ‹ et « Suivant » en haut, image finale en 9:16, durée « 00:01 / 00:19 »,
// lecture, annuler / rétablir, puis la frise des clips sous une tête de lecture fixe (faire défiler la frise déplace la
// lecture), « + » pour ajouter des vidéos, son coupé pour tous. Sans clip choisi : « Modifier », « Texte », « Filtres » ;
// un clip choisi (toucher) : « Diviser », « Supprimer », « Vitesse », « Recadrer », « Volume », « Rotation », et ses bords
// se déplacent au doigt pour le découper.
struct TimelineEditorView: View {
    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    let draft: PublishDraftViewModel
    let container: AppContainer
    let onBack: () -> Void
    let onNext: () -> Void
    @State private var editingText: TextDraft?
    @State private var isPickingFilter = false
    @State private var isAddingVideos = false
    @State private var isAddingClips = false
    @State private var cropping: CropRequest?
    // Position de la frise : décalage horizontal = instant × points par seconde.
    @State private var scroll = ScrollPosition(x: 0)
    // Le doigt fait défiler la frise : la lecture suit la frise (et non l'inverse).
    @State private var isScrubbing = false
    // « Appliquer à tout » des panneaux vitesse et volume.
    @State private var appliesToAll = false

    private static let rulerHeight: CGFloat = 22
    private static let stripHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            topBar
            EditorCanvas(model: model, preview: preview, cornerRadius: 0) { overlay in editingText = TextDraft(overlay: overlay) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 8)
            controls
            timeline
                .frame(height: Self.rulerHeight + Self.stripHeight + 40)
                .padding(.top, 8)
            if let panel = model.panel {
                panelView(panel)
            } else {
                toolbar
            }
        }
        .background(Color(white: 0.07).ignoresSafeArea())
        .overlay {
            if isAddingClips {
                ProgressView("Préparation…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(item: $editingText) { draft in
            TextOverlaySheet(draft: draft) { result in apply(result, to: draft) }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $isPickingFilter) {
            FilterPickerSheet(model: model)
                .presentationDetents([.height(170)])
                .presentationBackground(.black.opacity(0.85))
        }
        .sheet(isPresented: $isAddingVideos) {
            GalleryPickerView(model: container.makeGallery(kind: .video)) { assets in
                isAddingVideos = false
                addVideos(assets)
            }
        }
        .fullScreenCover(item: $cropping) { request in
            CropEditorView(request: request) { crop, ratio in
                model.setCrop(crop, ratio: ratio)
            }
        }
        // La frise suit la tête de lecture (lecture, annuler, clip divisé…), sauf quand le doigt la fait défiler.
        .onChange(of: preview.currentTime) { _, time in
            guard !isScrubbing else { return }
            scroll.scrollTo(x: time.seconds * VideoEditorViewModel.pointsPerSecond)
        }
        .onAppear { scroll.scrollTo(x: preview.currentTime.seconds * VideoEditorViewModel.pointsPerSecond) }
    }

    private var topBar: some View {
        HStack {
            Button("Retour", systemImage: "chevron.left") {
                preview.pause()
                model.deselect()
                onBack()
            }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.12), in: Circle())
            .accessibilityIdentifier("timeline.back")
            Spacer()
            Button(action: onNext) {
                Text("Suivant")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.brandPink, in: Capsule())
            }
            .disabled(!model.canFinish)
            .opacity(model.canFinish ? 1 : 0.5)
            .accessibilityIdentifier("timeline.next")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // « 00:01 / 00:19 », lecture, annuler / rétablir.
    private var controls: some View {
        ZStack {
            HStack(spacing: 4) {
                Text(TimelineTime.label(preview.currentTime)).foregroundStyle(.white)
                Text("/ \(TimelineTime.label(model.plan.outputDuration))").foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button("Annuler", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("timeline.undo")
                Button("Rétablir", systemImage: "arrow.uturn.forward") { model.redo() }
                    .disabled(!model.canRedo)
                    .padding(.leading, 18)
                    .accessibilityIdentifier("timeline.redo")
            }
            .font(.subheadline.monospacedDigit())
            .labelStyle(.iconOnly)
            .tint(.white)
            Button(preview.isPlaying ? "Pause" : "Lecture", systemImage: preview.isPlaying ? "pause.fill" : "play.fill") {
                preview.togglePlayback()
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(.white)
            .accessibilityIdentifier("timeline.play")
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .foregroundStyle(model.problem == nil ? .white : .orange)
        .overlay(alignment: .top) {
            if let problem = model.problem {
                Text(problem)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .offset(y: -18)
                    .accessibilityIdentifier("editor.problem")
            }
        }
    }

    // Frise : règle et clips dans un défilement horizontal, tête de lecture fixe au centre.
    private var timeline: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            ZStack(alignment: .leading) {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 6) {
                        TimelineRuler(duration: model.plan.outputDuration)
                            .frame(height: Self.rulerHeight)
                        HStack(spacing: 2) {
                            ForEach(model.plan.clips) { clip in
                                ClipStrip(model: model, clip: clip, height: Self.stripHeight)
                            }
                            Button("Ajouter des vidéos", systemImage: "plus") {
                                preview.pause()
                                isAddingVideos = true
                            }
                            .labelStyle(.iconOnly)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.leading, 8)
                            .accessibilityIdentifier("timeline.add")
                        }
                    }
                    .padding(.leading, half)
                    .padding(.trailing, half)
                }
                .scrollIndicators(.hidden)
                .scrollPosition($scroll)
                .onScrollPhaseChange { _, phase in
                    isScrubbing = phase == .interacting || phase == .decelerating
                    if phase == .interacting { preview.pause() }
                }
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentOffset.x
                } action: { _, offset in
                    guard isScrubbing else { return }
                    let seconds = max(0, offset) / VideoEditorViewModel.pointsPerSecond
                    preview.seek(to: min(.milliseconds(Int64(seconds * 1000)), model.plan.outputDuration))
                }
                // Son d'origine coupé pour tous les clips.
                Button(
                    model.plan.isMuted ? "Rétablir le son" : "Couper le son",
                    systemImage: model.plan.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                ) {
                    model.toggleMuted()
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 56, height: Self.stripHeight)
                .background(
                    LinearGradient(colors: [Color(white: 0.07), Color(white: 0.07).opacity(0)], startPoint: .leading, endPoint: .trailing)
                )
                .offset(y: Self.rulerHeight / 2 + 3)
                .accessibilityIdentifier("timeline.mute")
                // Tête de lecture.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: Self.rulerHeight + Self.stripHeight + 30)
                    .offset(x: half - 1)
                    .allowsHitTesting(false)
            }
        }
    }

    // Outils : sans clip choisi, ou ceux du clip choisi.
    @ViewBuilder
    private var toolbar: some View {
        if model.selectedClip != nil {
            HStack(spacing: 0) {
                Button("Fermer les outils du clip", systemImage: "chevron.down") { model.deselect() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .padding(.leading, 12)
                    .accessibilityIdentifier("timeline.deselect")
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        toolButton("Diviser", systemImage: "square.split.2x1", identifier: "timeline.split") { model.split(at: preview.currentTime) }
                        toolButton("Supprimer", systemImage: "trash", identifier: "timeline.delete") { model.deleteSelectedClip() }
                            .disabled(!model.canDeleteClip)
                        toolButton("Vitesse", systemImage: "gauge.with.dots.needle.67percent", identifier: "timeline.speed") {
                            appliesToAll = false
                            model.panel = .speed
                        }
                        toolButton("Recadrer", systemImage: "crop", identifier: "timeline.crop") { openCrop() }
                        toolButton("Volume", systemImage: "speaker.wave.2", identifier: "timeline.volume") {
                            appliesToAll = false
                            model.panel = .volume
                        }
                        toolButton("Rotation", systemImage: "rotate.right", identifier: "timeline.rotate") { model.rotateSelectedClip() }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: 76)
        } else {
            HStack(spacing: 0) {
                toolButton("Modifier", systemImage: "scissors", identifier: "timeline.edit") { model.selectClip(at: preview.currentTime) }
                toolButton("Texte", systemImage: "textformat", identifier: "timeline.text") {
                    if model.canAddText { editingText = TextDraft(overlay: nil) } else { model.errorMessage = "\(EditPlan.maxTexts) textes au plus." }
                }
                toolButton("Filtres", systemImage: "camera.filters", identifier: "timeline.filters") { isPickingFilter = true }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
        }
    }

    private func toolButton(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2.weight(.semibold))
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .frame(width: 72)
        }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func panelView(_ panel: VideoEditorViewModel.Panel) -> some View {
        let clip = model.selectedClip
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    appliesToAll.toggle()
                    // Réglage déjà choisi : appliqué à tous les clips dès que l'option est cochée.
                    if appliesToAll, let clip {
                        if panel == .speed { model.setSpeed(clip.speed, applyToAll: true) } else { model.setVolume(clip.volume, applyToAll: true) }
                        model.endInteraction()
                    }
                } label: {
                    Label("Appliquer à tout", systemImage: appliesToAll ? "checkmark.square.fill" : "square.stack.3d.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appliesToAll ? Color.brandPink : .white)
                }
                .accessibilityIdentifier("timeline.applyAll")
                Spacer()
                Button("Fermer", systemImage: "xmark") {
                    model.endInteraction()
                    model.panel = nil
                }
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.12), in: Circle())
                .accessibilityIdentifier("timeline.closePanel")
            }
            switch panel {
            case .speed:
                MarkedSlider(
                    value: SpeedScale.fraction(of: clip?.speed ?? 1), marks: SpeedScale.marks.map(SpeedScale.label),
                    bubble: { SpeedScale.label(SpeedScale.speed(at: $0)) }
                ) { fraction in
                    model.setSpeed(SpeedScale.speed(at: fraction), applyToAll: appliesToAll)
                } onEnded: {
                    model.endInteraction()
                }
                .accessibilityIdentifier("timeline.speedSlider")
            case .volume:
                MarkedSlider(
                    value: clip?.volume ?? 1, marks: ["0", "50", "100"], bubble: { "\(Int(($0 * 100).rounded()))" }
                ) { fraction in
                    model.setVolume((fraction * 100).rounded() / 100, applyToAll: appliesToAll)
                } onEnded: {
                    model.endInteraction()
                }
                .accessibilityIdentifier("timeline.volumeSlider")
            }
        }
        .padding(16)
        .background(Color(white: 0.13), in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
    }

    private func openCrop() {
        guard let clip = model.selectedClip else { return }
        preview.pause()
        Task {
            let image = await model.frame(of: clip)
            cropping = CropRequest(clip: clip, image: image)
        }
    }

    // Vidéos ajoutées par « + » : préparées (métadonnées retirées), puis mises au bout de la frise.
    private func addVideos(_ assets: [LibraryAsset]) {
        guard !assets.isEmpty else { return }
        let library = container.mediaLibrary
        isAddingClips = true
        Task {
            defer { isAddingClips = false }
            do {
                let clips = try await draft.prepareClips(assets.map { asset in { try await library.exportVideo(asset) } })
                model.append(clips)
            } catch {
                model.errorMessage = AppError.from(error).message
            }
        }
    }

    private func apply(_ result: TextOverlaySheet.Result, to draft: TextDraft) {
        switch result {
        case .save(let text, let color, let size):
            if let id = draft.overlay?.id {
                model.updateText(id, text: text, color: color, size: size)
            } else {
                model.addText(text, color: color, size: size)
            }
        case .delete:
            if let id = draft.overlay?.id { model.removeText(id) }
        }
    }
}

// « 00:01 », « 01:30 ».
enum TimelineTime {
    static func label(_ duration: Duration) -> String {
        let seconds = max(0, Int(duration.seconds))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// Règle : « 00:00 », « 00:02 »… toutes les 2 s, un point entre deux.
private struct TimelineRuler: View {
    let duration: Duration

    var body: some View {
        let step = VideoEditorViewModel.pointsPerSecond
        let count = Int(duration.seconds / 2) + 1
        ZStack(alignment: .leading) {
            ForEach(0..<count, id: \.self) { index in
                Text(TimelineTime.label(.seconds(index * 2)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize()
                    .frame(width: 40)
                    .offset(x: Double(index * 2) * step - 20)
                Circle()
                    .fill(.white.opacity(0.4))
                    .frame(width: 3, height: 3)
                    .offset(x: (Double(index * 2) + 1) * step - 1.5)
            }
        }
        .frame(width: max(1, duration.seconds * step), alignment: .leading)
        .accessibilityHidden(true)
    }
}

// Clip de la frise : miniatures sur la largeur de sa durée finale, durée et réglages en haut à gauche ; choisi (toucher),
// bordure blanche et poignées pour déplacer son début et sa fin.
private struct ClipStrip: View {
    let model: VideoEditorViewModel
    let clip: EditClip
    let height: CGFloat
    @State private var dragBase: (start: Duration, end: Duration)?

    private static let handleWidth: CGFloat = 16

    var body: some View {
        let key = model.thumbnailKey(for: clip)
        let width = max(8, clip.outputDuration.seconds * VideoEditorViewModel.pointsPerSecond)
        let selected = model.selectedClipID == clip.id
        HStack(spacing: 0) {
            ForEach(Array((model.thumbnails[key] ?? []).enumerated()), id: \.offset) { _, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width / CGFloat(max(1, key.count)), height: height)
                    .clipped()
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topLeading) { badges }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if selected { handle(isStart: true).offset(x: -Self.handleWidth) }
        }
        .overlay(alignment: .trailing) {
            if selected { handle(isStart: false).offset(x: Self.handleWidth) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(clip.id) }
        .task(id: key) { await model.loadThumbnails(key) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clip de \(clip.outputDuration.seconds.formatted(.number.precision(.fractionLength(1)))) secondes")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("timeline.clip")
    }

    private var badges: some View {
        HStack(spacing: 4) {
            Text("\(clip.outputDuration.seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US"))))s")
            if clip.volume == 0 || model.plan.isMuted { Image(systemName: "speaker.slash.fill") }
            if clip.speed != 1 {
                Label(SpeedScale.label(clip.speed), systemImage: "gauge.with.dots.needle.67percent").labelStyle(.titleAndIcon)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
        .padding(3)
    }

    // Poignée blanche : glisser déplace le début (ou la fin) du clip dans son fichier d'origine.
    private func handle(isStart: Bool) -> some View {
        Image(systemName: isStart ? "chevron.compact.left" : "chevron.compact.right")
            .font(.headline.weight(.bold))
            .foregroundStyle(.black)
            .frame(width: Self.handleWidth, height: height)
            .background(
                .white,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: isStart ? 6 : 0, bottomLeadingRadius: isStart ? 6 : 0,
                    bottomTrailingRadius: isStart ? 0 : 6, topTrailingRadius: isStart ? 0 : 6)
            )
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = dragBase ?? (clip.start, clip.end)
                        dragBase = base
                        // Points → secondes de la vidéo finale → secondes du fichier d'origine.
                        let delta = Duration.milliseconds(Int64(value.translation.width / VideoEditorViewModel.pointsPerSecond * clip.speed * 1000))
                        if isStart { model.setStart(base.start + delta, of: clip.id) } else { model.setEnd(base.end + delta, of: clip.id) }
                    }
                    .onEnded { _ in
                        dragBase = nil
                        model.endInteraction()
                    }
            )
            .accessibilityLabel(isStart ? "Début du clip" : "Fin du clip")
            .accessibilityIdentifier(isStart ? "timeline.trimStart" : "timeline.trimEnd")
    }
}

// Curseur à graduations, comme TikTok : repères en haut, traits, rond blanc ; bulle de la valeur pendant le geste.
private struct MarkedSlider: View {
    let value: Double
    let marks: [String]
    let bubble: (Double) -> String
    let onChange: (Double) -> Void
    let onEnded: () -> Void
    @State private var dragging: Double?

    private static let ticks = 20

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let position = dragging ?? value
            ZStack(alignment: .topLeading) {
                ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                    Text(mark)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize()
                        .frame(width: 60)
                        .position(x: width * Double(index) / Double(max(1, marks.count - 1)), y: 10)
                }
                ForEach(0...Self.ticks, id: \.self) { index in
                    let major = index % (Self.ticks / max(1, marks.count - 1)) == 0
                    Capsule()
                        .fill(.white.opacity(major ? 1 : 0.5))
                        .frame(width: 2, height: major ? 22 : 14)
                        .position(x: width * Double(index) / Double(Self.ticks), y: 46)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .shadow(radius: 2)
                    .position(x: width * position, y: 46)
                if let dragging {
                    Text(bubble(dragging))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.3), in: RoundedRectangle(cornerRadius: 8))
                        .position(x: min(max(width * dragging, 30), width - 30), y: 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / max(1, width), 0), 1)
                        dragging = fraction
                        onChange(fraction)
                    }
                    .onEnded { _ in
                        dragging = nil
                        onEnded()
                    }
            )
        }
        .frame(height: 64)
        .padding(.horizontal, 14)
        .accessibilityElement()
        .accessibilityValue(bubble(value))
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / Double(Self.ticks)
            onChange(min(max(value + (direction == .increment ? step : -step), 0), 1))
            onEnded()
        }
    }
}
