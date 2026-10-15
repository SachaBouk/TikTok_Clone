import Observation
import SwiftUI

// Historique de visionnage (privé) : grille du plus récent au plus ancien, rangée par jour de visionnage (ADR-057),
// même lecteur que le feed. Effacement manuel (choix du développeur) : une vidéo, une sélection, ou tout l'historique.
@MainActor
@Observable
final class ViewHistoryViewModel {
    let list: PagedList<FeedVideo>
    var errorMessage: String?

    private let removeFromHistory: RemoveFromHistoryUseCase
    private let clearHistory: ClearHistoryUseCase
    private let session: SessionStore

    init(loadVideoPage: LoadVideoPageUseCase, removeFromHistory: RemoveFromHistoryUseCase, clearHistory: ClearHistoryUseCase, session: SessionStore) {
        self.removeFromHistory = removeFromHistory
        self.clearHistory = clearHistory
        self.session = session
        list = PagedList(session: session) { cursor in
            try await loadVideoPage(.myHistory, cursor: cursor).asPage
        }
    }

    var sections: [DaySection<FeedVideo>] { DaySections.group(list.items, date: \.viewedAt) }

    func remove(_ video: FeedVideo) async {
        await remove([video.id])
    }

    // Une requête par vidéo ; à la première erreur, les vidéos déjà retirées disparaissent et le message s'affiche.
    func remove(_ ids: Set<String>) async {
        for id in list.items.map(\.id) where ids.contains(id) {
            do {
                try await removeFromHistory(videoID: id)
                list.remove { $0.id == id }
            } catch {
                errorMessage = handle(error)
                return
            }
        }
    }

    func clear() async {
        do {
            try await clearHistory()
            list.remove { _ in true }
        } catch {
            errorMessage = handle(error)
        }
    }

    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        return error.message
    }
}

struct ViewHistoryView: View {
    @State private var viewModel: ViewHistoryViewModel
    let container: AppContainer
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var isConfirmingClear = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(viewModel: ViewHistoryViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.sections) { section in
                    Text(section.title)
                        .font(.title2.bold())
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(section.items) { video in
                            cell(video)
                                .onAppear { Task { await viewModel.list.loadMore(ifNeededAfter: video) } }
                        }
                    }
                }
            }
            footer
        }
        .navigationTitle("Historique de visionnage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Annuler" : "Sélectionner") {
                    isSelecting.toggle()
                    selection = []
                }
                .disabled(viewModel.list.items.isEmpty && !isSelecting)
                .accessibilityIdentifier("history.select")
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Tout effacer", role: .destructive) { isConfirmingClear = true }
                        .accessibilityIdentifier("history.clear")
                    Spacer()
                    Button("Supprimer (\(selection.count))", role: .destructive) {
                        let ids = selection
                        selection = []
                        isSelecting = false
                        Task { await viewModel.remove(ids) }
                    }
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("history.delete")
                }
            }
        }
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .task { await viewModel.list.loadFirstIfNeeded() }
        .refreshable { await viewModel.list.loadFirst() }
        .onChange(of: container.videoInteractions.deletedVideoIDs) { _, ids in viewModel.list.remove { ids.contains($0.id) } }
        .onChange(of: container.videoInteractions.blockedUserIDs) { _, ids in viewModel.list.remove { ids.contains($0.author.id) } }
        .confirmationDialog("Effacer tout l’historique de visionnage ?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Effacer l’historique", role: .destructive) {
                selection = []
                isSelecting = false
                Task { await viewModel.clear() }
            }
        } message: {
            Text("Les vues déjà comptées sur les vidéos ne changent pas.")
        }
        .alert(
            "Historique",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // Toucher ouvre le lecteur vertical sur la vidéo (avec la suite de l'historique), ou la coche en sélection.
    @ViewBuilder
    private func cell(_ video: FeedVideo) -> some View {
        let thumbnail = VideoGridCell(thumbnailURL: video.thumbnailURL, image: nil, views: video.stats.views)
        Group {
            if isSelecting {
                Button {
                    if selection.contains(video.id) { selection.remove(video.id) } else { selection.insert(video.id) }
                } label: {
                    thumbnail.overlay(alignment: .topTrailing) { SelectionMark(isSelected: selection.contains(video.id)) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.contains(video.id) ? .isSelected : [])
            } else if let index = viewModel.list.items.firstIndex(where: { $0.id == video.id }) {
                NavigationLink(
                    value: VideoPlayerRoute(
                        list: .myHistory, page: FeedPage(videos: viewModel.list.items, nextCursor: viewModel.list.nextCursor), startIndex: index)
                ) { thumbnail }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Retirer de l’historique", systemImage: "minus.circle", role: .destructive) {
                        Task { await viewModel.remove(video) }
                    }
                }
            }
        }
        .accessibilityLabel(video.description ?? "Vidéo de @\(video.author.username)")
    }

    @ViewBuilder
    private var footer: some View {
        let list = viewModel.list
        switch list.state {
        case .idle, .loading:
            if list.items.isEmpty { ProgressView().padding(.vertical, 40).frame(maxWidth: .infinity) }
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Réessayer") { Task { await list.loadFirst() } }
            }
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        case .loaded:
            if list.items.isEmpty {
                ContentUnavailableView("Aucune vidéo regardée", systemImage: "play.rectangle").padding(.vertical, 24)
            }
        }
    }
}

// Rond de sélection, en haut à droite d'une miniature.
private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? Color.brandPink : .black.opacity(0.25))
            .shadow(color: .black.opacity(0.4), radius: 2)
            .padding(6)
    }
}

// Historique des commentaires (privé) : chaque commentaire avec la vidéo commentée ; toucher ouvre la vidéo,
// glisser supprime le commentaire.
@MainActor
@Observable
final class CommentHistoryViewModel {
    let list: PagedList<CommentHistoryEntry>
    var errorMessage: String?

    private let deleteComment: DeleteCommentUseCase
    private let interactions: VideoInteractionsModel
    private let session: SessionStore

    init(loadComments: LoadCommentHistoryUseCase, deleteComment: DeleteCommentUseCase, interactions: VideoInteractionsModel, session: SessionStore) {
        self.deleteComment = deleteComment
        self.interactions = interactions
        self.session = session
        list = PagedList(session: session) { cursor in
            let page = try await loadComments(cursor: cursor)
            return (page.entries, page.nextCursor)
        }
    }

    // Son compte, en tête de chaque ligne (ADR-057).
    var me: UserSummary? {
        session.profile.map { UserSummary(id: $0.id, username: $0.username, displayName: $0.displayName, avatarURL: $0.avatarURL) }
    }

    // Comptes bloqués depuis le chargement : les commentaires sur leurs vidéos disparaissent (l'API ne les renvoie plus).
    var blockedUserIDs: Set<String> { interactions.blockedUserIDs }

    func removeBlocked(_ ids: Set<String>) {
        list.remove { ids.contains($0.video.author.id) }
    }

    func delete(_ entry: CommentHistoryEntry) async {
        do {
            try await deleteComment(id: entry.id)
            list.remove { $0.id == entry.id }
        } catch {
            let error = AppError.from(error)
            if error == .sessionExpired {
                session.sessionExpired()
            } else {
                errorMessage = error.message
            }
        }
    }
}

struct CommentHistoryView: View {
    @State private var viewModel: CommentHistoryViewModel
    let router: AppRouter

    init(viewModel: CommentHistoryViewModel, router: AppRouter) {
        _viewModel = State(initialValue: viewModel)
        self.router = router
    }

    var body: some View {
        List {
            ForEach(viewModel.list.items) { entry in
                Button {
                    router.presentedVideo = AppRouter.VideoRoute(id: entry.video.id)
                } label: {
                    CommentHistoryRow(entry: entry, me: viewModel.me)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        Task { await viewModel.delete(entry) }
                    }
                }
                .onAppear { Task { await viewModel.list.loadMore(ifNeededAfter: entry) } }
            }
        }
        .listStyle(.plain)
        .overlay {
            PagedListPlaceholder(
                state: viewModel.list.state, isEmpty: viewModel.list.items.isEmpty, emptyTitle: "Aucun commentaire",
                emptySystemImage: "text.bubble"
            ) { await viewModel.list.loadFirst() }
        }
        .navigationTitle("Historique des commentaires")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.list.loadFirstIfNeeded() }
        .refreshable { await viewModel.list.loadFirst() }
        .onChange(of: viewModel.blockedUserIDs) { _, ids in viewModel.removeBlocked(ids) }
        .alert(
            "Commentaires",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// Ligne comme TikTok : sa photo, « Nom ▸ auteur de la vidéo », le commentaire et sa date, la miniature à droite.
private struct CommentHistoryRow: View {
    let entry: CommentHistoryEntry
    let me: UserSummary?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: me?.avatarURL, name: me?.displayName ?? "", size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(me?.displayName ?? "Toi")
                    if entry.video.author.id != me?.id {
                        Image(systemName: "arrowtriangle.right.fill").font(.caption2)
                        Text(entry.video.author.displayName)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Text(
                    "\(entry.content)  \(Text(.currentDate, format: RelativeTime.style(for: entry.createdAt)).foregroundStyle(.secondary).font(.subheadline))"
                )
                .lineLimit(4)
            }
            Spacer(minLength: 8)
            VideoGridCell(thumbnailURL: entry.video.thumbnailURL, image: nil, views: nil)
                .frame(width: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
