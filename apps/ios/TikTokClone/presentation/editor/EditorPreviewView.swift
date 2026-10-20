import SwiftUI

// Éditeur de la création (ADR-062) : écran d'aperçu, puis éditeur par clips (« Modifier »). Son modèle et son lecteur
// sont créés une fois, à l'apparition (le contenu d'un écran présenté est réévalué à chaque mise à jour).
struct EditorFlowView: View {
    let request: EditorRequest
    let draft: PublishDraftViewModel
    let container: AppContainer
    // Story publiée par « Ta story » : la création se ferme.
    let onStoryPublished: () -> Void
    @State private var editor: (model: VideoEditorViewModel, preview: EditorPreviewPlayer)?
    @State private var isEditingClips = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let editor {
                Group {
                    if isEditingClips {
                        TimelineEditorView(model: editor.model, preview: editor.preview, draft: draft, container: container) {
                            isEditingClips = false
                        } onNext: {
                            next(editor)
                        }
                    } else {
                        EditorPreviewView(
                            model: editor.model, preview: editor.preview, draft: draft, container: container,
                            onEditClips: { isEditingClips = true }, onNext: { next(editor) }, onStory: { story(editor) }, onBack: { back(editor) })
                    }
                }
                .disabled(editor.model.isExporting)
                .overlay {
                    if editor.model.isExporting {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Préparation de la vidéo…")
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .environment(\.colorScheme, .dark)
                    }
                }
                // Rendu changé : l'aperçu est relu à la même position, après un court délai (gestes en cours).
                .task(id: editor.model.previewVersion) {
                    let version = editor.model.previewVersion
                    if version > 0 { try? await Task.sleep(for: .milliseconds(250)) }
                    guard !Task.isCancelled else { return }
                    let wasPlaying = version == 0 || editor.preview.isPlaying
                    await editor.preview.load(editor.model.plan, at: version == 0 ? nil : editor.preview.currentTime, autoplay: wasPlaying)
                }
                .onChange(of: isEditingClips, initial: true) { _, editing in
                    // L'éditeur par clips lit jusqu'au bout ; l'aperçu tourne en boucle.
                    editor.preview.loops = !editing
                    if editing { editor.preview.pause() } else { editor.preview.play() }
                }
                .alert(
                    "Édition",
                    isPresented: Binding(get: { editor.model.errorMessage != nil }, set: { if !$0 { editor.model.errorMessage = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(editor.model.errorMessage ?? "")
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            if editor == nil { editor = (container.makeVideoEditor(request), EditorPreviewPlayer()) }
        }
        .onDisappear { editor?.preview.stop() }
    }

    // « Suivant » : la vidéo est exportée, puis l'écran de publication s'ouvre.
    private func next(_ editor: (model: VideoEditorViewModel, preview: EditorPreviewPlayer)) {
        // Aperçu en pause pendant l'export : il ne lui dispute pas le processeur.
        editor.preview.pause()
        Task {
            if let result = await editor.model.finish() {
                editor.preview.stop()
                await draft.edited(result, request: request)
            } else {
                editor.preview.play()
            }
        }
    }

    // « Ta story » : 60 s au plus, exportée puis publiée en story.
    private func story(_ editor: (model: VideoEditorViewModel, preview: EditorPreviewPlayer)) {
        if let problem = editor.model.storyProblem {
            editor.model.errorMessage = problem
            return
        }
        editor.preview.pause()
        Task {
            guard let result = await editor.model.finish() else {
                editor.preview.play()
                return
            }
            editor.preview.stop()
            if draft.publishStory(result, source: request.source) { onStoryPublished() }
        }
    }

    // ‹ de l'aperçu : la vidéo est abandonnée (fichiers d'origine, vidéos ajoutées et vidéo déjà exportée), retour à la
    // caméra.
    private func back(_ editor: (model: VideoEditorViewModel, preview: EditorPreviewPlayer)) {
        editor.preview.stop()
        editor.model.discard()
        if !request.isNew { draft.discard() }
        draft.editorClosed()
    }
}

// Aperçu, comme TikTok : la vidéo en grand, « ♫ Ajouter un son » en haut (ADR-064), outils à droite (Réglages, Modifier,
// Texte, Autocollants, Effets, Filtres, Voix ; ⌄ affiche leurs noms), « Ta story » et « Suivant » en bas. Textes et autocollants se déplacent au doigt ; un texte se
// modifie d'un toucher. Le panneau des filtres s'ouvre en bas, par-dessus (ADR-063).
struct EditorPreviewView: View {
    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    let draft: PublishDraftViewModel
    let container: AppContainer
    let onEditClips: () -> Void
    let onNext: () -> Void
    let onStory: () -> Void
    let onBack: () -> Void
    @State private var editingText: TextDraft?
    @State private var isDraggingText = false
    @State private var isPickingFilter = false
    @State private var isPickingSticker = false
    @State private var isEditingEffects = false
    // Sons et voix (ADR-064).
    @State private var isPickingSound = false
    @State private var isShowingVolume = false
    @State private var isTrimmingSound = false
    @State private var isEditingVoice = false
    @State private var flashFilter: VideoFilter?
    @State private var thumbnails = LookThumbnailStore()
    @State private var isShowingSettings = false
    @State private var showsToolNames = false
    @State private var confirmingDiscard = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                EditorCanvas(model: model, preview: preview, hiddenTextID: editingText?.overlay?.id, isDraggingText: $isDraggingText) {
                    overlay in editingText = TextDraft(overlay: overlay)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    // Panneau ouvert (filtres, sons, volume) : un toucher sur la vidéo le ferme.
                    if isPickingFilter || isPickingSound || isShowingVolume {
                        isPickingFilter = false
                        isPickingSound = false
                        isShowingVolume = false
                    } else {
                        preview.togglePlayback()
                    }
                }
                .overlay {
                    if let flashFilter { FilterFlash(filter: flashFilter) }
                }
                HStack(alignment: .top) {
                    backButton
                    Spacer()
                    tools
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .opacity(showsControls ? 1 : 0)
                notice
                    .padding(.top, 64)
                    .opacity(showsControls ? 1 : 0)
                // Son repris (ADR-064) : vidéos seulement, pas les stories.
                if draft.mode == .video {
                    SoundPill(model: model) { isPickingSound = true }
                        .padding(.top, 10)
                        .opacity(showsControls || isPickingSound ? 1 : 0)
                        .allowsHitTesting(showsControls)
                }
            }
            bottomBar
                .opacity(showsControls ? 1 : 0)
                .allowsHitTesting(showsControls)
        }
        .background(Color.black.ignoresSafeArea())
        // Le clavier de l'éditeur de texte passe par-dessus la vidéo sans la déplacer.
        .ignoresSafeArea(.keyboard)
        .overlay {
            if let draft = editingText {
                TextEditorOverlay(draft: draft) { text, style in
                    model.finishEditingText(draft.overlay, text: text, style: style)
                    editingText = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isPickingFilter {
                FilterPanel(model: model, thumbnails: thumbnails)
                    .transition(.move(edge: .bottom))
            } else if isShowingVolume {
                SoundVolumePanel(model: model) { isShowingVolume = false }
                    .transition(.move(edge: .bottom))
            } else if isPickingSound {
                SoundPanel(model: model, library: container.sounds) {
                    isPickingSound = false
                    isShowingVolume = true
                } onTrim: {
                    isTrimmingSound = true
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy(duration: 0.25), value: isPickingSound)
        .animation(.snappy(duration: 0.25), value: isShowingVolume)
        .sheet(isPresented: $isTrimmingSound) {
            SoundTrimSheet(model: model).presentationDetents([.height(280)])
        }
        .fullScreenCover(isPresented: $isEditingVoice) {
            VoiceEffectsView(model: model, preview: preview, makeRecorder: { container.makeVoiceRecorder() })
        }
        .animation(.easeOut(duration: 0.15), value: isDraggingText)
        .animation(.snappy(duration: 0.25), value: isPickingFilter)
        .animation(.easeOut(duration: 0.3), value: flashFilter)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { preview.play() } else { preview.pause() }
        }
        .onChange(of: model.plan.filter) { _, filter in
            if isPickingFilter, filter != .none { flashFilter = filter }
        }
        .task(id: flashFilter) {
            guard flashFilter != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { flashFilter = nil }
        }
        .sheet(isPresented: $isPickingSticker) {
            StickerPickerView { kind, text in model.addSticker(kind, emoji: text) }
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isEditingEffects) {
            EffectsEditorView(model: model, preview: preview, thumbnails: thumbnails)
        }
        .sheet(isPresented: $isShowingSettings) {
            PostSettingsSheet(draft: draft)
        }
    }

    // Boutons masqués pendant la saisie ou le déplacement d'un texte, et sous le panneau des filtres, comme TikTok.
    private var showsControls: Bool { editingText == nil && !isDraggingText && !isPickingFilter && !isPickingSound && !isShowingVolume }

    private var backButton: some View {
        Button("Retour", systemImage: "chevron.left") { confirmingDiscard = true }
            .labelStyle(.iconOnly)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .shadow(radius: 3)
            .confirmationDialog("Abandonner la vidéo ?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive, action: onBack)
            } message: {
                Text(model.request.source == .camera ? "Les segments filmés seront supprimés." : "Les modifications seront perdues.")
            }
            .accessibilityIdentifier("editor.back")
    }

    // Outils à droite ; leurs noms s'affichent avec ⌄.
    private var tools: some View {
        VStack(alignment: .trailing, spacing: 18) {
            if draft.mode == .video {
                tool("Réglages", systemImage: "gearshape", identifier: "editor.settings") { isShowingSettings = true }
                Divider().frame(width: 28).overlay(.white.opacity(0.5))
            }
            tool("Modifier", systemImage: "slider.horizontal.below.rectangle", identifier: "editor.clips", action: onEditClips)
            tool("Texte", systemImage: "textformat", identifier: "editor.addText") {
                if model.canAddText { editingText = TextDraft(overlay: nil) } else { model.errorMessage = "\(EditPlan.maxTexts) textes au plus." }
            }
            tool("Autocollants", systemImage: "face.smiling", identifier: "editor.stickers") {
                if model.canAddSticker { isPickingSticker = true } else { model.errorMessage = "\(EditPlan.maxStickers) autocollants au plus." }
            }
            tool("Effets", systemImage: "sparkles", identifier: "editor.effects", badge: !model.plan.effects.isEmpty) {
                preview.pause()
                isEditingEffects = true
            }
            tool("Filtres", systemImage: "camera.filters", identifier: "editor.filters", badge: model.plan.filter != .none) {
                isPickingFilter = true
            }
            if draft.mode == .video {
                tool("Voix", systemImage: "waveform.and.mic", identifier: "editor.voice", badge: !model.plan.voiceovers.isEmpty) {
                    preview.pause()
                    isEditingVoice = true
                }
            }
            Button(showsToolNames ? "Masquer les noms" : "Afficher les noms", systemImage: showsToolNames ? "chevron.up" : "chevron.down") {
                withAnimation(.snappy) { showsToolNames.toggle() }
            }
            .labelStyle(.iconOnly)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.white.opacity(0.2), in: Circle())
            .padding(.trailing, 4)
        }
    }

    // `badge` : coche rose quand l'outil est utilisé (effets posés, filtre choisi), comme TikTok.
    private func tool(_ title: String, systemImage: String, identifier: String, badge: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 10) {
                if showsToolNames {
                    Text(title).font(.subheadline.weight(.semibold)).transition(.opacity)
                }
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 36)
                    .overlay(alignment: .bottomTrailing) {
                        if badge {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                                .background(Color.brandPink, in: Circle())
                                .offset(x: -2, y: 2)
                        }
                    }
            }
            .foregroundStyle(.white)
            .shadow(radius: 3)
        }
        .accessibilityLabel(title)
        .accessibilityValue(badge ? "Utilisé" : "")
        .accessibilityIdentifier(identifier)
    }

    // Problème en cours (orange), sinon le message de départ (vidéo de la galerie trop longue).
    @ViewBuilder
    private var notice: some View {
        if let message = model.problem ?? model.request.notice {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(model.problem == nil ? Color.white : Color.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 72)
                .accessibilityIdentifier("editor.problem")
        } else if preview.isSimplified {
            Text("Aperçu simplifié : filtre et cadre non affichés")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.5), in: Capsule())
        }
    }

    // « Ta story » (avec sa photo) et « Suivant » ; en mode Story, « Ta story » seul.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: onStory) {
                HStack(spacing: 8) {
                    AvatarView(url: container.session.profile?.avatarURL, name: container.session.profile?.displayName ?? "", size: 28)
                        .padding(2)
                        .overlay(Circle().stroke(Color.brandCyan, lineWidth: 2))
                    Text("Ta story").font(.headline)
                }
                .foregroundStyle(draft.mode == .story ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(draft.mode == .story ? Color.brandPink : .white, in: RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!model.canFinish)
            .accessibilityIdentifier("editor.story")
            if draft.mode == .video {
                Button(action: onNext) {
                    Text("Suivant")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!model.canFinish)
                .opacity(model.canFinish ? 1 : 0.5)
                .accessibilityIdentifier("editor.done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// Image finale en 9:16 : la composition du plan, les textes par-dessus (déplacés au doigt, pincés, touchés pour les
// modifier). Pendant un déplacement : repère central et corbeille « Supprimer » (`isDraggingText` : l'écran masque ses
// boutons, comme TikTok). Le texte en cours de modification (`hiddenTextID`) est montré par l'éditeur de texte.
struct EditorCanvas: View {
    static let coordinateSpace = "editorCanvas"

    private struct DragState: Equatable {
        var onGuide: Bool
        var overTrash: Bool
    }

    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    var cornerRadius: CGFloat = 12
    var hiddenTextID: UUID?
    @Binding var isDraggingText: Bool
    let onEditText: (TextOverlay) -> Void
    @State private var drag: DragState?

    var body: some View {
        // Aperçu simplifié (simulateur, sans composition) : la vidéo brute est ajustée dans le 9:16, comme à l'export.
        PlayerLayerView(player: preview.player, fills: !preview.isSimplified)
            .aspectRatio(preview.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        if let drag {
                            TextDragGuides(onGuide: drag.onGuide, overTrash: drag.overTrash)
                        }
                        // Autocollants sous les textes, comme à l'export.
                        ForEach(model.plan.stickers) { sticker in
                            self.sticker(sticker, size: geometry.size)
                        }
                        ForEach(model.plan.texts.filter { $0.id != hiddenTextID }) { overlay in
                            text(overlay, size: geometry.size)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .coordinateSpace(.named(Self.coordinateSpace))
                }
            }
            .overlay {
                if preview.failed {
                    Label("Aperçu indisponible", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                }
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityIdentifier("editor.preview")
    }

    private func text(_ overlay: TextOverlay, size: CGSize) -> some View {
        DraggableOverlay(
            center: overlay.center, scale: overlay.scale, size: size, label: overlay.text,
            hint: "Touche pour modifier le texte, glisse-le pour le déplacer", identifier: "editor.text"
        ) { scale in
            StyledTextBox(text: overlay.text, layout: EditorTextStyle(style: overlay.style, scale: scale, width: size.width))
        } onDragChanged: { center, finger in
            dragChanged(center: center, finger: finger)
        } onDragEnded: { center, finger in
            dragEnded(finger: finger) {
                model.removeText(overlay.id)
            } move: {
                model.moveText(overlay.id, to: center)
            }
        } onScale: { scale in
            model.scaleText(overlay.id, to: scale)
        } onTap: {
            onEditText(overlay)
        }
    }

    private func sticker(_ sticker: StickerOverlay, size: CGSize) -> some View {
        DraggableOverlay(
            center: sticker.center, scale: sticker.scale, size: size,
            label: sticker.kind == .emoji ? sticker.text : "\(sticker.kind.title) \(sticker.text)",
            hint: "Glisse-le pour le déplacer, pince-le pour changer sa taille", identifier: "editor.sticker"
        ) { scale in
            StickerView(sticker: sticker, scale: scale, width: size.width)
        } onDragChanged: { center, finger in
            dragChanged(center: center, finger: finger)
        } onDragEnded: { center, finger in
            dragEnded(finger: finger) {
                model.removeSticker(sticker.id)
            } move: {
                model.moveSticker(sticker.id, to: center)
            }
        } onScale: { scale in
            model.scaleSticker(sticker.id, to: scale)
        }
    }

    private func dragChanged(center: CGPoint, finger: CGPoint) {
        drag = DragState(onGuide: abs(center.x - 0.5) < 0.0001, overTrash: TextDragRules.isOverTrash(finger))
        isDraggingText = true
    }

    // Lâché sur la corbeille : supprimé ; ailleurs : déplacé.
    private func dragEnded(finger: CGPoint, remove: () -> Void, move: () -> Void) {
        drag = nil
        isDraggingText = false
        if TextDragRules.isOverTrash(finger) { remove() } else { move() }
    }
}
