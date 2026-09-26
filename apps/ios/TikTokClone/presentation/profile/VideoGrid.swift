import SwiftUI

// Grille de vidéos en 3 colonnes (profil, historique de visionnage). Toucher une vidéo ouvre le lecteur
// vertical sur elle, avec la suite de la liste. Les pages suivantes se chargent à l'approche de la fin.
struct VideoGrid: View {
    let list: PagedList<FeedVideo>
    var pending: [PublishingModel.Publication] = []
    var previews: [String: UIImage] = [:]
    let route: (FeedPage, Int) -> VideoPlayerRoute?
    let emptyTitle: String
    var onPendingTap: (PublishingModel.Publication) -> Void = { _ in }
    // Action du menu contextuel d'une vidéo (historique : « Retirer de l'historique »).
    var removeTitle: String?
    var onRemove: (FeedVideo) -> Void = { _ in }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(pending) { publication in
                    PendingVideoCell(publication: publication, preview: previews[publication.id])
                        .onTapGesture { onPendingTap(publication) }
                }
                ForEach(Array(list.items.enumerated()), id: \.element.id) { index, video in
                    cell(video, index: index)
                        .onAppear { Task { await list.loadMore(ifNeededAfter: video) } }
                }
            }
            footer
        }
        .accessibilityIdentifier("profile.grid")
    }

    @ViewBuilder
    private func cell(_ video: FeedVideo, index: Int) -> some View {
        let thumbnail = VideoGridCell(thumbnailURL: video.thumbnailURL, image: nil, views: video.stats.views)
        Group {
            if let route = route(FeedPage(videos: list.items, nextCursor: list.nextCursor), index) {
                NavigationLink(value: route) { thumbnail }
                    .buttonStyle(.plain)
            } else {
                thumbnail
            }
        }
        .contextMenu {
            if let removeTitle {
                Button(removeTitle, systemImage: "minus.circle", role: .destructive) { onRemove(video) }
            }
        }
        .accessibilityLabel(video.description ?? "Vidéo de @\(video.author.username)")
    }

    @ViewBuilder
    private var footer: some View {
        switch list.state {
        case .idle, .loading:
            if list.items.isEmpty {
                ProgressView().padding(.vertical, 40)
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Réessayer") { Task { await list.loadFirst() } }
            }
            .padding(.vertical, 32)
        case .loaded:
            if list.items.isEmpty && pending.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "video")
                    .padding(.vertical, 24)
            }
        }
    }
}

// Miniature verticale 9:16, avec le nombre de vues.
struct VideoGridCell: View {
    let thumbnailURL: URL?
    let image: UIImage?
    let views: Int?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let thumbnailURL {
                    AsyncImage(url: thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.secondarySystemBackground)
                    }
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let views {
                    Label {
                        Text(views, format: .number.notation(.compactName))
                    } icon: {
                        Image(systemName: "play")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .padding(6)
                    .accessibilityLabel("\(views) vues")
                }
            }
            .contentShape(Rectangle())
    }
}

// Publication pas encore en ligne, en tête de sa grille.
private struct PendingVideoCell: View {
    let publication: PublishingModel.Publication
    let preview: UIImage?

    var body: some View {
        VideoGridCell(thumbnailURL: publication.thumbnailURL, image: preview, views: nil)
            .overlay {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 6) {
                        if publication.phase == .failed {
                            Image(systemName: "exclamationmark.triangle.fill").font(.title3)
                            Text("Échec").font(.caption.bold())
                        } else {
                            ProgressView().tint(.white)
                            Text("Publication…").font(.caption.bold())
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(publication.phase == .failed ? "Publication en échec" : "Publication en cours")
    }
}
