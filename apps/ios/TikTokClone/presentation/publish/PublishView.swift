import PhotosUI
import SwiftUI

// Onglet « Publier » (ADR-016 : upload simple depuis la galerie, sans édition) : choix de la vidéo,
// description, puis suivi des publications (envoi, traitement, mise en ligne).
struct PublishView: View {
    @State private var draft: PublishDraftViewModel
    let publishing: PublishingModel
    let router: AppRouter
    @State private var pickerItem: PhotosPickerItem?
    @State private var alertMessage: String?
    @FocusState private var isEditingDescription: Bool

    init(draft: PublishDraftViewModel, publishing: PublishingModel, router: AppRouter) {
        _draft = State(initialValue: draft)
        self.publishing = publishing
        self.router = router
    }

    var body: some View {
        @Bindable var draft = draft
        NavigationStack {
            Form {
                Section {
                    draftContent
                } header: {
                    Text("Nouvelle vidéo")
                } footer: {
                    if case .empty = draft.state {
                        Text("MP4 ou MOV, 1 Go au plus. La vidéo est publiée telle quelle.")
                    }
                }

                if !publishing.publications.isEmpty {
                    Section("Publications") {
                        ForEach(publishing.publications) { publication in
                            PublicationRow(
                                publication: publication,
                                preview: publishing.previews[publication.id],
                                retry: { publishing.retry(publication.id) },
                                open: { publication.videoID.map { router.presentedVideo = AppRouter.VideoRoute(id: $0) } },
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
                Task { await draft.load { try await item.loadTransferable(type: PickedVideo.self)?.url } }
            }
            .alert("Publication", isPresented: Binding(
                get: { alertMessage != nil || draft.errorMessage != nil },
                set: { if !$0 { alertMessage = nil; draft.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? draft.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var draftContent: some View {
        @Bindable var draft = draft
        switch draft.state {
        case .empty:
            picker(title: "Choisir une vidéo")
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Préparation de la vidéo…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
            picker(title: "Choisir une autre vidéo")
        case .ready(let video):
            HStack(alignment: .top, spacing: 12) {
                VideoThumbnail(image: video.preview, url: nil, duration: video.duration)
                    .frame(width: 90, height: 160)
                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Décris ta vidéo", text: $draft.description, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($isEditingDescription)
                        .accessibilityIdentifier("publish.description")
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
            picker(title: "Changer de vidéo")
            Button("Annuler", role: .destructive) { draft.discard() }
        }
    }

    private func picker(title: String) -> some View {
        // `.current` : la vidéo telle qu'enregistrée (HEVC compris), sans conversion préalable par la galerie ;
        // le transcodage est fait par le serveur (ADR-008).
        PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
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
                Text(publication.description ?? "Sans description")
                    .lineLimit(2)
                    .foregroundStyle(publication.description == nil ? .secondary : .primary)
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
