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

// Aperçu, comme TikTok : la vidéo en grand, outils à droite (Réglages, Modifier, Texte, Filtres ; ⌄ affiche leurs noms),
// « Ta story » et « Suivant » en bas. Les textes se déplacent au doigt et se modifient d'un toucher.
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
    @State private var isPickingFilter = false
    @State private var isShowingSettings = false
    @State private var showsToolNames = false
    @State private var confirmingDiscard = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                EditorCanvas(model: model, preview: preview) { overlay in editingText = TextDraft(overlay: overlay) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { preview.togglePlayback() }
                HStack(alignment: .top) {
                    backButton
                    Spacer()
                    tools
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                notice
                    .padding(.top, 64)
            }
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { preview.play() } else { preview.pause() }
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
        .sheet(isPresented: $isShowingSettings) {
            PostSettingsSheet(draft: draft)
        }
    }

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
            tool("Filtres", systemImage: "camera.filters", identifier: "editor.filters") { isPickingFilter = true }
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

    private func tool(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showsToolNames {
                    Text(title).font(.subheadline.weight(.semibold)).transition(.opacity)
                }
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 36)
            }
            .foregroundStyle(.white)
            .shadow(radius: 3)
        }
        .accessibilityLabel(title)
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

// Image finale en 9:16 : la composition du plan, les textes par-dessus (déplacés au doigt, touchés pour les modifier).
struct EditorCanvas: View {
    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    var cornerRadius: CGFloat = 12
    let onEditText: (TextOverlay) -> Void

    var body: some View {
        // Aperçu simplifié (simulateur, sans composition) : la vidéo brute est ajustée dans le 9:16, comme à l'export.
        PlayerLayerView(player: preview.player, fills: !preview.isSimplified)
            .aspectRatio(preview.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ForEach(model.plan.texts) { overlay in
                        DraggableText(overlay: overlay, size: geometry.size) { center in
                            model.moveText(overlay.id, to: center)
                        } onTap: {
                            onEditText(overlay)
                        }
                    }
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
}

// Filtres : une rangée de pastilles, appliqués à toute la vidéo (aperçu et éditeur par clips).
struct FilterPickerSheet: View {
    let model: VideoEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filtres").font(.headline).foregroundStyle(.white).padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VideoFilter.allCases) { filter in
                        let selected = model.plan.filter == filter
                        Button {
                            model.setFilter(filter)
                        } label: {
                            Text(filter.title)
                                .font(.subheadline.weight(selected ? .bold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(selected ? Color.white : Color.white.opacity(0.15), in: Capsule())
                                .foregroundStyle(selected ? .black : .white)
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("editor.filter.\(filter.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 20)
        .environment(\.colorScheme, .dark)
    }
}
