import PhotosUI
import SwiftUI

// Onglet « Publier » : vidéo filmée par la caméra ou choisie dans la galerie, modifiée au besoin dans l'éditeur
// (ADR-052), description, puis suivi des publications (envoi, traitement, mise en ligne). Sélecteur « Vidéo | Story »
// (ADR-051) : une story est une vidéo de 60 s au plus ou une photo, sans description, visible 24 h.
struct PublishView: View {
    @State private var draft: PublishDraftViewModel
    let publishing: PublishingModel
    let router: AppRouter
    let container: AppContainer
    @State private var pickerItem: PhotosPickerItem?
    @State private var alertMessage: String?
    @State private var camera: CameraSetup?
    // Rendu de la caméra, traité à sa fermeture (l'éditeur ne peut s'ouvrir qu'une fois la caméra fermée).
    @State private var cameraOutcome: CameraOutcome?
    @FocusState private var isEditingDescription: Bool

    init(draft: PublishDraftViewModel, publishing: PublishingModel, router: AppRouter, container: AppContainer) {
        _draft = State(initialValue: draft)
        self.publishing = publishing
        self.router = router
        self.container = container
    }

    var body: some View {
        @Bindable var draft = draft
        NavigationStack {
            Form {
                Section {
                    Picker("Publier", selection: $draft.mode) {
                        ForEach(PublishDraftViewModel.Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("publish.mode")
                }
                Section {
                    draftContent
                } header: {
                    Text(draft.mode == .story ? "Nouvelle story" : "Nouvelle vidéo")
                } footer: {
                    if case .empty = draft.state {
                        Text(
                            draft.mode == .story
                                ? "Une vidéo de 60 secondes au plus, ou une photo (recadrée en 9:16). Visible 24 heures, sans sa position."
                                : "3 minutes et 1 Go au plus, sans sa position. Découpe, vitesse, filtres et textes dans l’éditeur.")
                    }
                }

                if !publishing.publications.isEmpty {
                    Section("Publications") {
                        ForEach(publishing.publications) { publication in
                            PublicationRow(
                                publication: publication,
                                preview: publishing.previews[publication.id],
                                retry: { publishing.retry(publication.id) },
                                open: { open(publication) },
                                delete: { delete(publication) }
                            )
                            .swipeActions { swipeActions(for: publication) }
                        }
                    }
                }
            }
            .navigationTitle("Publier")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // La description est multiligne : retour à la ligne au clavier, « OK » pour le fermer.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { isEditingDescription = false }
                }
            }
            .refreshable { await publishing.refresh() }
            .task { await publishing.refresh() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                // Pour pouvoir choisir à nouveau la même vidéo.
                pickerItem = nil
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                Task {
                    await draft.loadMedia {
                        if isVideo { return try await item.loadTransferable(type: PickedVideo.self).map { .video($0.url) } }
                        return try await item.loadTransferable(type: PickedPhoto.self).map { .photo($0.data) }
                    }
                }
            }
            // « + » de « Ta story » (boîte de réception) : mode Story.
            .onChange(of: router.requestedPublishMode, initial: true) { _, mode in
                guard let mode else { return }
                draft.mode = mode
                router.requestedPublishMode = nil
            }
            .fullScreenCover(item: $camera, onDismiss: cameraClosed) { setup in
                CameraView(model: setup.model, preview: CameraPreview(session: setup.session)) { outcome in
                    cameraOutcome = outcome
                    camera = nil
                } onCancel: {
                    camera = nil
                }
            }
            .alert(
                "Publication",
                isPresented: Binding(
                    get: { alertMessage != nil || draft.errorMessage != nil },
                    set: {
                        if !$0 {
                            alertMessage = nil
                            draft.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? draft.errorMessage ?? "")
            }
        }
        .fullScreenCover(item: Binding(get: { draft.editorRequest }, set: { if $0 == nil { draft.editorClosed() } })) { request in
            EditorScreen(request: request, container: container) { result in
                Task { await draft.edited(result, request: request) }
            } onCancel: {
                draft.editorClosed()
            }
        }
    }

    private func cameraClosed() {
        guard let outcome = cameraOutcome else { return }
        cameraOutcome = nil
        switch outcome {
        case .segments(let segments):
            draft.recorded(segments)
        case .photo(let data):
            Task { await draft.loadMedia(source: .camera) { .photo(data) } }
        }
    }

    // « Filmer » et « Choisir dans la galerie ».
    @ViewBuilder
    private func sources(galleryTitle: String) -> some View {
        Button {
            camera = container.makeCamera(kind: draft.kind)
        } label: {
            Label(draft.mode == .story ? "Filmer ou photographier" : "Filmer", systemImage: "camera")
        }
        .accessibilityIdentifier("publish.camera")
        picker(title: galleryTitle)
    }

    private var editButton: some View {
        Button {
            draft.editCurrent()
        } label: {
            Label("Modifier la vidéo", systemImage: "wand.and.stars")
        }
        .disabled(!draft.canEdit)
        .accessibilityIdentifier("publish.edit")
    }

    @ViewBuilder
    private var draftContent: some View {
        @Bindable var draft = draft
        switch draft.state {
        case .empty:
            sources(galleryTitle: draft.mode == .story ? "Choisir une vidéo ou une photo" : "Choisir dans la galerie")
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text(draft.mode == .story ? "Préparation…" : "Préparation de la vidéo…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
            sources(galleryTitle: draft.mode == .story ? "Choisir un autre média" : "Choisir une autre vidéo")
        case .ready(let video) where draft.mode == .story:
            HStack(alignment: .top, spacing: 12) {
                VideoThumbnail(image: video.preview, url: nil, duration: video.duration)
                    .frame(width: 90, height: 160)
                Text(video.isPhoto ? "Photo affichée 5 secondes, visible 24 heures." : "Vidéo visible 24 heures.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                draft.publish()
            } label: {
                Label("Publier la story", systemImage: "circle.dashed.inset.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canPublish)
            .accessibilityIdentifier("publish.submit")
            if draft.canEdit { editButton }
            picker(title: "Changer de média")
            Button("Annuler", role: .destructive) { draft.discard() }
        case .ready(let video):
            HStack(alignment: .top, spacing: 12) {
                VideoThumbnail(image: video.preview, url: nil, duration: video.duration)
                    .frame(width: 90, height: 160)
                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Décris ta vidéo", text: $draft.description, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($isEditingDescription)
                        .accessibilityIdentifier("publish.description")
                    hashtagSuggestions
                    Text(draft.remainingCharacters, format: .number)
                        .font(.caption)
                        .foregroundStyle(draft.remainingCharacters < 0 ? .red : .secondary)
                        .accessibilityLabel("\(draft.remainingCharacters) caractères restants")
                }
            }
            .padding(.vertical, 4)
            Button {
                isEditingDescription = false
                draft.publish()
            } label: {
                Label("Publier", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canPublish)
            .accessibilityIdentifier("publish.submit")
            if draft.canEdit { editButton }
            picker(title: "Changer de vidéo")
            Button("Annuler", role: .destructive) { draft.discard() }
        }
    }

    // Suggestions en écrivant « # » (ADR-049) : toucher complète le hashtag en cours de saisie.
    @ViewBuilder
    private var hashtagSuggestions: some View {
        if !draft.hashtagSuggestions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(draft.hashtagSuggestions) { hashtag in
                        Button {
                            draft.applySuggestion(hashtag)
                        } label: {
                            Text("\(hashtag.title) · \(hashtag.videosCount.formatted(.number.notation(.compactName)))")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("\(hashtag.title), \(hashtag.videosLabel)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("publish.hashtagSuggestions")
        }
    }

    private func picker(title: String) -> some View {
        // `.current` : la vidéo telle qu'enregistrée (HEVC compris), sans conversion préalable par la galerie ;
        // le transcodage est fait par le serveur (ADR-008). Une story peut aussi être une photo (ADR-051).
        PhotosPicker(
            selection: $pickerItem, matching: draft.mode == .story ? .any(of: [.videos, .images]) : .videos, preferredItemEncoding: .current
        ) {
            Label(title, systemImage: "photo.on.rectangle")
        }
        .accessibilityIdentifier("publish.pick")
    }

    @ViewBuilder
    private func swipeActions(for publication: PublishingModel.Publication) -> some View {
        switch publication.phase {
        case .waiting, .uploading, .interrupted:
            Button("Annuler", systemImage: "xmark", role: .destructive) { delete(publication) }
        case .processing, .failed:
            Button("Supprimer", systemImage: "trash", role: .destructive) { delete(publication) }
        case .ready:
            Button("Masquer", systemImage: "eye.slash") { publishing.dismiss(publication.id) }
        }
    }

    // « Voir » : la vidéo seule, ou sa story dans la visionneuse.
    private func open(_ publication: PublishingModel.Publication) {
        guard let videoID = publication.videoID else { return }
        if publication.kind == .story {
            guard let me = publishing.ownSummary else { return }
            router.openStories([me], source: .profile)
        } else {
            router.presentedVideo = AppRouter.VideoRoute(id: videoID)
        }
    }

    private func delete(_ publication: PublishingModel.Publication) {
        Task { alertMessage = await publishing.delete(publication.id) }
    }
}

private struct PublicationRow: View {
    let publication: PublishingModel.Publication
    let preview: UIImage?
    let retry: () -> Void
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VideoThumbnail(image: preview, url: publication.thumbnailURL, duration: nil)
                .frame(width: 54, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(publication.kind == .story ? "Story" : publication.description ?? "Sans description")
                    .lineLimit(2)
                    .foregroundStyle(publication.description == nil && publication.kind == .video ? .secondary : .primary)
                status
                    .font(.subheadline)
                    .accessibilityIdentifier("publication.status")
            }
            Spacer(minLength: 0)
            action
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publication.row")
    }

    @ViewBuilder
    private var status: some View {
        switch publication.phase {
        case .waiting:
            Text("En attente d’envoi…").foregroundStyle(.secondary)
        case .uploading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text("Envoi… \(progress, format: .percent.precision(.fractionLength(0)))").foregroundStyle(.secondary)
            }
        case .interrupted(let message):
            Text(message).foregroundStyle(.red)
        case .processing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Traitement en cours…").foregroundStyle(.secondary)
            }
        case .ready:
            outcome("Publiée", systemImage: "checkmark.circle.fill", color: .green)
        case .failed:
            outcome("Échec du traitement", systemImage: "exclamationmark.triangle.fill", color: .red)
        }
    }

    private func outcome(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var action: some View {
        switch publication.phase {
        case .interrupted:
            Button("Réessayer", action: retry).buttonStyle(.borderless)
        case .ready:
            Button("Voir", action: open).buttonStyle(.borderless)
        case .failed:
            Button("Supprimer", role: .destructive, action: delete).buttonStyle(.borderless)
        case .waiting, .uploading, .processing:
            EmptyView()
        }
    }
}

// Miniature verticale : aperçu local, sinon miniature de l'API, sinon icône.
private struct VideoThumbnail: View {
    let image: UIImage?
    let url: URL?
    let duration: Duration?

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration {
                    Text(duration, format: .time(pattern: .minuteSecond))
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .shadow(radius: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

// Éditeur plein écran : son modèle et son aperçu sont créés une seule fois, à l'apparition (le contenu d'un plein écran
// est réévalué à chaque mise à jour de l'écran qui le présente).
private struct EditorScreen: View {
    let request: EditorRequest
    let container: AppContainer
    let onFinish: (EditResult) -> Void
    let onCancel: () -> Void
    @State private var editor: (model: VideoEditorViewModel, preview: EditorPreviewPlayer)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let editor {
                VideoEditorView(model: editor.model, preview: editor.preview, onFinish: onFinish, onCancel: onCancel)
            }
        }
        .onAppear {
            if editor == nil { editor = (container.makeVideoEditor(request), EditorPreviewPlayer()) }
        }
    }
}
