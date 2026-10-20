import SwiftUI

// Création, plein écran par-dessus les onglets (bouton « + », ADR-062) : caméra (modes Caméra, Story, Live) et galerie
// maison, puis éditeur (aperçu et éditeur par clips), puis écran de publication ; une photo de story s'affiche avant
// « Ta story ». Publier ferme la création (le profil montre la publication en cours).
struct CreationView: View {
    @State private var draft: PublishDraftViewModel
    @State private var camera: CameraSetup
    let container: AppContainer
    // `story` : vrai pour une story publiée.
    let onPublished: (_ story: Bool) -> Void
    let onClose: () -> Void
    @State private var gallery: GalleryViewModel?
    @State private var importThumbnail: CGImage?

    init(
        draft: PublishDraftViewModel, camera: CameraSetup, container: AppContainer, onPublished: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        _camera = State(initialValue: camera)
        self.container = container
        self.onPublished = onPublished
        self.onClose = onClose
    }

    var body: some View {
        @Bindable var draft = draft
        ZStack {
            Color.black.ignoresSafeArea()
            if let request = draft.editorRequest {
                EditorFlowView(request: request, draft: draft, container: container, onStoryPublished: { onPublished(true) }, onDraftSaved: onClose)
                    .id(request.id)
            } else if case .ready(let video) = draft.state {
                if video.isPhoto {
                    PhotoStoryPreview(video: video, container: container) {
                        draft.discard()
                    } onPublish: {
                        if draft.publish() { onPublished(true) }
                    }
                } else {
                    PostView(draft: draft, video: video, container: container) {
                        onPublished(false)
                    } onDraftSaved: {
                        onClose()
                    }
                }
            } else {
                CameraView(
                    model: camera.model, preview: CameraPreview(session: camera.session), mode: $draft.mode, liveTitle: $draft.liveTitle,
                    importThumbnail: importThumbnail
                ) { outcome in
                    switch outcome {
                    case .segments(let segments): draft.recorded(segments)
                    case .photo(let data): Task { await draft.loadMedia(source: .camera) { .photo(data) } }
                    }
                } onImport: {
                    gallery = container.makeGallery(kind: draft.kind)
                } onStartLive: {
                    let title = draft.liveTitle
                    draft.liveTitle = ""
                    container.router.startLive(title: title)
                } onClose: {
                    onClose()
                }
                .task { await loadImportThumbnail() }
            }
            if draft.state == .loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(draft.mode == .story ? "Préparation…" : "Préparation de la vidéo…")
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .environment(\.colorScheme, .dark)
            }
        }
        .sheet(item: $gallery) { model in
            GalleryPickerView(model: model) { assets in
                gallery = nil
                load(assets)
            }
        }
        .alert(
            "Publication",
            isPresented: Binding(
                get: { draft.errorMessage != nil || failure != nil },
                set: {
                    if !$0 {
                        draft.errorMessage = nil
                        if failure != nil { draft.discard() }
                    }
                })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(draft.errorMessage ?? failure ?? "")
        }
    }

    private var failure: String? {
        if case .failed(let message) = draft.state { return message }
        return nil
    }

    // Médias choisis : vidéos mises bout à bout dans l'éditeur, ou photo de story.
    private func load(_ assets: [LibraryAsset]) {
        guard let first = assets.first else { return }
        let library = container.mediaLibrary
        Task {
            if first.isVideo {
                await draft.loadVideos(assets.filter(\.isVideo).map { asset in { try await library.exportVideo(asset) } })
            } else {
                await draft.loadMedia { .photo(try await library.photoData(first)) }
            }
        }
    }

    // Dernier média de la galerie sur « Importer », sans demander l'autorisation (elle l'est à l'ouverture de la galerie).
    private func loadImportThumbnail() async {
        let library = container.mediaLibrary
        guard library.access().canRead else { return }
        let filter: LibraryFilter = draft.mode == .story ? .all : .videos
        guard let latest = await library.assets(in: nil, filter: filter).first else { return }
        importThumbnail = await library.thumbnail(of: latest, side: 120)
    }
}

// Création présentée en plein écran : brouillon et caméra créés une seule fois, à l'apparition (le contenu d'un plein
// écran est réévalué à chaque mise à jour de l'écran qui le présente).
struct CreationScreen: View {
    let container: AppContainer
    let mode: PublishDraftViewModel.Mode
    // Brouillon rouvert (ADR-065).
    var restoring: VideoDraft?
    let onPublished: (Bool) -> Void
    let onClose: () -> Void
    @State private var setup: (draft: PublishDraftViewModel, camera: CameraSetup)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let setup {
                CreationView(draft: setup.draft, camera: setup.camera, container: container, onPublished: onPublished, onClose: onClose)
            }
        }
        .onAppear {
            guard setup == nil else { return }
            let draft = container.makePublishDraftViewModel()
            draft.mode = mode
            if let restoring { draft.restore(restoring) }
            setup = (draft, container.makeCamera(kind: draft.kind))
        }
    }
}

extension GalleryViewModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

// Photo de story (galerie ou caméra) : affichée en grand, « Ta story » la publie.
private struct PhotoStoryPreview: View {
    let video: PublishDraftViewModel.Draft
    let container: AppContainer
    let onBack: () -> Void
    let onPublish: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Color.black
                .overlay {
                    if let preview = video.preview { Image(uiImage: preview).resizable().scaledToFit() }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Button("Retour", systemImage: "chevron.left", action: onBack)
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                        .padding(8)
                        .accessibilityIdentifier("story.back")
                }
            Button(action: onPublish) {
                HStack(spacing: 8) {
                    AvatarView(url: container.session.profile?.avatarURL, name: container.session.profile?.displayName ?? "", size: 28)
                        .padding(2)
                        .overlay(Circle().stroke(Color.brandCyan, lineWidth: 2))
                    Text("Ta story").font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("publish.submit")
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}
