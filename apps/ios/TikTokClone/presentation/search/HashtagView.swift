import Observation
import SwiftUI

// Page d'un hashtag (ADR-049) : nom, nombre de vidéos et grille, de la vidéo la plus récemment publiée à la plus
// ancienne. Toucher une vidéo ouvre le lecteur vertical sur la liste du hashtag.
@MainActor
@Observable
final class HashtagViewModel {
    let name: String
    let videos: PagedList<FeedVideo>
    private(set) var hashtag: Hashtag?

    private let loadHashtag: LoadHashtagUseCase
    private let interactions: VideoInteractionsModel

    init(name: String, loadHashtag: LoadHashtagUseCase, loadVideos: LoadVideoListUseCase, interactions: VideoInteractionsModel, session: SessionStore)
    {
        self.name = name
        self.loadHashtag = loadHashtag
        self.interactions = interactions
        videos = PagedList(session: session) { cursor in try await loadVideos.page(cursor: cursor).asPage }
    }

    var title: String { "#\(name)" }

    // Vidéos supprimées ou de comptes bloqués depuis le chargement : retirées de la grille.
    var hiddenVideoIDs: Set<String> { interactions.deletedVideoIDs }
    var blockedUserIDs: Set<String> { interactions.blockedUserIDs }

    func load() async {
        async let header: Void = loadHeader()
        await videos.loadFirstIfNeeded()
        await header
    }

    func refresh() async {
        async let header: Void = loadHeader()
        await videos.loadFirst()
        await header
    }

    func removeHidden() {
        videos.remove { hiddenVideoIDs.contains($0.id) || blockedUserIDs.contains($0.author.id) }
    }

    private func loadHeader() async {
        if let loaded = try? await loadHashtag(name: name) { hashtag = loaded }
    }
}

struct HashtagView: View {
    @State private var viewModel: HashtagViewModel

    init(viewModel: HashtagViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                VideoGrid(
                    list: viewModel.videos,
                    route: { page, index in VideoPlayerRoute(list: .hashtag(name: viewModel.name), page: page, startIndex: index) },
                    emptyTitle: "Aucune vidéo pour ce hashtag"
                )
            }
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: viewModel.hiddenVideoIDs) { viewModel.removeHidden() }
        .onChange(of: viewModel.blockedUserIDs) { viewModel.removeHidden() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "number")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 80, height: 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title).font(.title2.bold()).lineLimit(2)
                if let hashtag = viewModel.hashtag {
                    Text(hashtag.videosLabel).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hashtag.header")
    }
}
