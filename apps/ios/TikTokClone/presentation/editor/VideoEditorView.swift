import SwiftUI

// Éditeur plein écran (ADR-052) : aperçu en boucle (découpage, vitesse et filtre appliqués par la même composition que
// l'export ; textes déplaçables par-dessus), puis outils « Découper | Vitesse | Filtres | Texte ». « Terminé » exporte.
struct VideoEditorView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case trim
        case speed
        case filter
        case text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trim: "Découper"
            case .speed: "Vitesse"
            case .filter: "Filtres"
            case .text: "Texte"
            }
        }
    }

    @State private var model: VideoEditorViewModel
    @State private var preview: EditorPreviewPlayer
    let onFinish: (EditResult) -> Void
    let onCancel: () -> Void
    @State private var tool: Tool = .trim
    @State private var editingText: TextDraft?
    @State private var confirmingDiscard = false
    @Environment(\.scenePhase) private var scenePhase

    init(model: VideoEditorViewModel, preview: EditorPreviewPlayer, onFinish: @escaping (EditResult) -> Void, onCancel: @escaping () -> Void) {
        _model = State(initialValue: model)
        _preview = State(initialValue: preview)
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar
            previewArea
            status
            Picker("Outil", selection: $tool) {
                ForEach(Tool.allCases) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("editor.tool")
            toolPanel
                .frame(height: 96)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .disabled(model.isExporting)
        .overlay {
            if model.isExporting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Préparation de la vidéo…")
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .environment(\.colorScheme, .dark)
            }
        }
        // Découpage, vitesse ou filtre changés : l'aperçu est relu, après un court délai (glissement de la frise).
        .task(id: model.previewVersion) {
            if model.previewVersion > 0 { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await preview.load(model.plan)
        }
        .task { await model.loadThumbnails(count: 10) }
        .onDisappear { preview.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { preview.play() } else { preview.pause() }
        }
        .sheet(item: $editingText) { draft in
            TextOverlaySheet(draft: draft) { result in
                apply(result, to: draft)
            }
            .presentationDetents([.medium])
        }
        .alert(
            "Édition",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button("Annuler") {
                if model.request.isNew { confirmingDiscard = true } else { cancel() }
            }
            .confirmationDialog("Abandonner la vidéo ?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { cancel() }
            } message: {
                Text(model.request.source == .camera ? "Les segments filmés seront supprimés." : "La vidéo ne sera pas publiée.")
            }
            Spacer()
            Text(model.plan.outputDuration, format: .time(pattern: .minuteSecond))
                .font(.headline.monospacedDigit())
                .foregroundStyle(model.problem == nil ? .white : .orange)
                .accessibilityLabel("Durée finale")
            Spacer()
            Button("Terminé") {
                // Aperçu en pause pendant l'export : il ne lui dispute pas le processeur.
                preview.pause()
                Task {
                    if let result = await model.finish() {
                        preview.stop()
                        onFinish(result)
                    } else {
                        preview.play()
                    }
                }
            }
            .bold()
            .disabled(!model.canFinish)
            .accessibilityIdentifier("editor.done")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // Image aux proportions de la vidéo finale ; textes placés en proportion, déplacés au doigt, touchés pour modifier.
    private var previewArea: some View {
        PlayerLayerView(player: preview.player)
            .aspectRatio(preview.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ForEach(model.plan.texts) { overlay in
                        DraggableText(overlay: overlay, size: geometry.size) { center in
                            model.moveText(overlay.id, to: center)
                        } onTap: {
                            editingText = TextDraft(overlay: overlay)
                        }
                    }
                }
            }
            .overlay {
                if preview.failed {
                    Label("Aperçu indisponible", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                }
            }
            .overlay(alignment: .top) {
                if preview.isSimplified {
                    Text("Aperçu simplifié : filtre non affiché")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("editor.preview")
    }

    @ViewBuilder
    private var status: some View {
        // Le problème en cours (orange), sinon le message de départ (vidéo de la galerie trop longue).
        if let message = model.problem ?? model.request.notice {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(model.problem == nil ? Color.secondary : Color.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("editor.problem")
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch tool {
        case .trim:
            VStack(spacing: 8) {
                TrimStrip(model: model)
                    .frame(height: 56)
                HStack {
                    Text(model.plan.trimStart, format: .time(pattern: .minuteSecond))
                    Spacer()
                    Text("Gardé : \(model.plan.trimmedDuration, format: .time(pattern: .minuteSecond))")
                    Spacer()
                    Text(model.plan.trimEnd, format: .time(pattern: .minuteSecond))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        case .speed:
            VStack(spacing: 8) {
                Picker("Vitesse", selection: Binding(get: { model.plan.speed }, set: { model.setSpeed($0) })) {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("editor.speed")
                Text("Toute la vidéo, son compris (hauteur gardée).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .filter:
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VideoFilter.allCases) { filter in
                        let selected = model.plan.filter == filter
                        Button {
                            model.setFilter(filter)
                        } label: {
                            Text(filter.title)
                                .font(.subheadline.weight(selected ? .bold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? Color.white : Color.white.opacity(0.15), in: Capsule())
                                .foregroundStyle(selected ? .black : .white)
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("editor.filter.\(filter.rawValue)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        case .text:
            VStack(spacing: 8) {
                Button {
                    editingText = TextDraft(overlay: nil)
                } label: {
                    Label("Ajouter un texte", systemImage: "textformat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAddText)
                .accessibilityIdentifier("editor.addText")
                Text(
                    model.plan.texts.isEmpty
                        ? "Visible pendant toute la vidéo. Déplace-le au doigt."
                        : "Touche un texte pour le modifier, fais-le glisser pour le déplacer."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func cancel() {
        preview.stop()
        model.discard()
        onCancel()
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

// Texte en cours de saisie : nouveau (`overlay` nil) ou existant.
struct TextDraft: Identifiable {
    let id = UUID()
    let overlay: TextOverlay?
}

// Texte de l'aperçu, aux proportions de l'export (`EditorTextStyle`) : glisser le déplace, toucher le modifie.
private struct DraggableText: View {
    let overlay: TextOverlay
    let size: CGSize
    let onMove: (CGPoint) -> Void
    let onTap: () -> Void
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        let style = EditorTextStyle(overlay: overlay, width: size.width)
        let rgb = overlay.color.rgb
        Text(overlay.text)
            .font(.system(size: style.fontSize, weight: .heavy))
            .foregroundStyle(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
            .multilineTextAlignment(.center)
            .shadow(color: overlay.color == .black ? .white.opacity(0.6) : .black.opacity(0.6), radius: style.shadowRadius)
            .frame(maxWidth: style.maxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .position(x: overlay.center.x * size.width + dragOffset.width, y: overlay.center.y * size.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        dragOffset = .zero
                        onMove(
                            CGPoint(
                                x: overlay.center.x + value.translation.width / size.width,
                                y: overlay.center.y + value.translation.height / size.height))
                    }
            )
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Touche pour modifier le texte")
    }
}

// Frise de découpage : miniatures de toute la durée d'origine, poignées de début et de fin, parties écartées assombries.
private struct TrimStrip: View {
    let model: VideoEditorViewModel
    private let handleWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - handleWidth * 2)
            let start = handleWidth + width * model.startFraction
            let end = handleWidth + width * model.endFraction
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width / CGFloat(max(1, model.thumbnails.count)), height: geometry.size.height)
                            .clipped()
                    }
                }
                .frame(width: width, height: geometry.size.height, alignment: .leading)
                .background(Color.white.opacity(0.1))
                .offset(x: handleWidth)
                Color.black.opacity(0.6).frame(width: max(0, start - handleWidth)).offset(x: handleWidth)
                Color.black.opacity(0.6).frame(width: max(0, handleWidth + width - end)).offset(x: end)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(width: max(0, end - start), height: geometry.size.height)
                    .offset(x: start)
                handle(systemImage: "chevron.compact.left", label: "Début", value: model.startFraction)
                    .offset(x: start - handleWidth)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trim")).onChanged { model.setTrimStart(fraction: ($0.location.x - handleWidth) / width) }
                    )
                handle(systemImage: "chevron.compact.right", label: "Fin", value: model.endFraction)
                    .offset(x: end)
                    .gesture(
                        DragGesture(coordinateSpace: .named("trim")).onChanged { model.setTrimEnd(fraction: ($0.location.x - handleWidth) / width) })
            }
            .coordinateSpace(.named("trim"))
        }
    }

    private func handle(systemImage: String, label: String, value: Double) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(.black)
            .frame(width: handleWidth)
            .frame(maxHeight: .infinity)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

// Saisie d'un texte : contenu, couleur, taille ; « Supprimer » pour un texte existant.
private struct TextOverlaySheet: View {
    enum Result {
        case save(String, TextOverlay.Color, TextOverlay.Size)
        case delete
    }

    let draft: TextDraft
    let onDone: (Result) -> Void
    @State private var text: String
    @State private var color: TextOverlay.Color
    @State private var size: TextOverlay.Size
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(draft: TextDraft, onDone: @escaping (Result) -> Void) {
        self.draft = draft
        self.onDone = onDone
        _text = State(initialValue: draft.overlay?.text ?? "")
        _color = State(initialValue: draft.overlay?.color ?? .white)
        _size = State(initialValue: draft.overlay?.size ?? .medium)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ton texte", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focused)
                        .accessibilityIdentifier("editor.textField")
                } footer: {
                    Text("\(EditPlan.maxTextLength - text.count) caractères restants")
                        .foregroundStyle(text.count > EditPlan.maxTextLength ? .red : .secondary)
                }
                Section("Couleur") {
                    HStack {
                        ForEach(TextOverlay.Color.allCases) { option in
                            let rgb = option.rgb
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                                    .overlay(
                                        Circle().stroke(
                                            option == color ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: option == color ? 3 : 1)
                                    )
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                            if option != TextOverlay.Color.allCases.last { Spacer(minLength: 0) }
                        }
                    }
                }
                Section("Taille") {
                    Picker("Taille", selection: $size) {
                        ForEach(TextOverlay.Size.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if draft.overlay != nil {
                    Section {
                        Button("Supprimer le texte", role: .destructive) {
                            onDone(.delete)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.overlay == nil ? "Nouveau texte" : "Modifier le texte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onDone(.save(text, color, size))
                        dismiss()
                    }
                    .disabled(EditPlan.sanitizedText(text) == nil && draft.overlay == nil)
                    .accessibilityIdentifier("editor.textDone")
                }
            }
            .onAppear { focused = true }
        }
    }
}
