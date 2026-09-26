import Observation
import SwiftUI

// Historique de visionnage (privé) : grille du plus récent au plus ancien, même lecteur que le feed.
// Effacement manuel (choix du développeur) : une vidéo, ou tout l'historique.
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

    func remove(_ video: FeedVideo) async {
        do {
            try await removeFromHistory(videoID: video.id)
            list.remove { $0.id == video.id }
        } catch {
            errorMessage = handle(error)
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
    @State private var isConfirmingClear = false

    init(viewModel: ViewHistoryViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
    }

    var body: some View {
        ScrollView {
            VideoGrid(
                list: viewModel.list,
                route: { page, index in VideoPlayerRoute(list: .myHistory, page: page, startIndex: index) },
                emptyTitle: "Aucune vidéo regardée",
                removeTitle: "Retirer de l’historique",
                onRemove: { video in Task { await viewModel.remove(video) } }
            )
        }
        .navigationTitle("Historique de visionnage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Effacer", role: .destructive) { isConfirmingClear = true }
                    .disabled(viewModel.list.items.isEmpty)
                    .accessibilityIdentifier("history.clear")
            }
        }
        .task { await viewModel.list.loadFirstIfNeeded() }
        .refreshable { await viewModel.list.loadFirst() }
        .onChange(of: container.videoInteractions.deletedVideoIDs) { _, ids in viewModel.list.remove { ids.contains($0.id) } }
        .confirmationDialog("Effacer tout l’historique de visionnage ?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Effacer l’historique", role: .destructive) { Task { await viewModel.clear() } }
        } message: {
            Text("Les vues déjà comptées sur les vidéos ne changent pas.")
        }
        .alert("Historique", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
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
    private let session: SessionStore

    init(loadComments: LoadCommentHistoryUseCase, deleteComment: DeleteCommentUseCase, session: SessionStore) {
        self.deleteComment = deleteComment
        self.session = session
        list = PagedList(session: session) { cursor in
            let page = try await loadComments(cursor: cursor)
            return (page.entries, page.nextCursor)
        }
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
                    CommentHistoryRow(entry: entry)
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
            PagedListPlaceholder(state: viewModel.list.state, isEmpty: viewModel.list.items.isEmpty, emptyTitle: "Aucun commentaire",
                                 emptySystemImage: "text.bubble") { await viewModel.list.loadFirst() }
        }
        .navigationTitle("Historique des commentaires")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.list.loadFirstIfNeeded() }
        .refreshable { await viewModel.list.loadFirst() }
        .alert("Commentaires", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct CommentHistoryRow: View {
    let entry: CommentHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VideoGridCell(thumbnailURL: entry.video.thumbnailURL, image: nil, views: nil)
                .frame(width: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content).lineLimit(3)
                Text("Sur la vidéo de @\(entry.video.author.username) · \(entry.createdAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
