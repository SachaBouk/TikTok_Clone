import SwiftUI

// Publications de la création (ADR-062) : envoi, traitement, mise en ligne ; « Réessayer », « Voir », « Supprimer »,
// glisser pour annuler ou masquer. Page ouverte depuis les vignettes « Publication… » de son profil.
struct PublicationsView: View {
    let publishing: PublishingModel
    let router: AppRouter
    @State private var alertMessage: String?

    var body: some View {
        List {
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
        .overlay {
            if publishing.publications.isEmpty {
                ContentUnavailableView(
                    "Aucune publication en cours", systemImage: "arrow.up.circle", description: Text("Tes vidéos en cours d’envoi apparaissent ici."))
            }
        }
        .navigationTitle("Publications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await publishing.refresh() }
        .task { await publishing.refresh() }
        .alert(
            "Publication",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
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
