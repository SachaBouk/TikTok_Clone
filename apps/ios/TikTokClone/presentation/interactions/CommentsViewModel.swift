import Foundation
import Observation

// Feuille de commentaires d'une vidéo : lisible par tous, écrire demande un compte (ADR-010).
@MainActor
@Observable
final class CommentsViewModel {
    let video: FeedVideo
    private(set) var comments: [VideoComment] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var count: Int
    private(set) var isSending = false
    var draft = ""
    var errorMessage: String?

    private let loadComments: LoadCommentsUseCase
    private let addComment: AddCommentUseCase
    private let deleteComment: DeleteCommentUseCase
    private let session: SessionStore
    // Prévient les autres écrans du nouveau nombre de commentaires (+1 / -1).
    private let onCountChange: (Int) -> Void
    private var nextCursor: String?
    private var hasLoaded = false

    init(
        video: FeedVideo,
        loadComments: LoadCommentsUseCase,
        addComment: AddCommentUseCase,
        deleteComment: DeleteCommentUseCase,
        session: SessionStore,
        onCountChange: @escaping (Int) -> Void
    ) {
        self.video = video
        self.count = video.stats.comments
        self.loadComments = loadComments
        self.addComment = addComment
        self.deleteComment = deleteComment
        self.session = session
        self.onCountChange = onCountChange
    }

    var isSignedIn: Bool { session.isSignedIn }
    var hasMore: Bool { nextCursor != nil }
    var canSend: Bool { CommentRules.sanitized(draft) != nil && !isSending }

    func isOwn(_ comment: VideoComment) -> Bool {
        session.profile?.id == comment.author.id
    }

    func start() async {
        guard !hasLoaded else { return }
        await load(cursor: nil)
    }

    func loadMore() async {
        guard let nextCursor, !isLoading else { return }
        await load(cursor: nextCursor)
    }

    func send() async {
        guard session.isSignedIn else { session.requestSignIn(); return }
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            let comment = try await addComment(videoID: video.id, text: draft)
            comments.insert(comment, at: 0)
            draft = ""
            count += 1
            onCountChange(1)
        } catch {
            report(error)
        }
    }

    // Suppression de son propre commentaire ; il revient à sa place si l'API refuse.
    func delete(_ comment: VideoComment) async {
        guard isOwn(comment), let index = comments.firstIndex(of: comment) else { return }
        comments.remove(at: index)
        count = max(0, count - 1)
        onCountChange(-1)
        do {
            try await deleteComment(id: comment.id)
        } catch {
            comments.insert(comment, at: min(index, comments.count))
            count += 1
            onCountChange(1)
            report(error)
        }
    }

    private func load(cursor: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await loadComments(videoID: video.id, cursor: cursor)
            comments += page.comments.filter { new in !comments.contains { $0.id == new.id } }
            nextCursor = page.nextCursor
            hasLoaded = true
            loadError = nil
        } catch {
            if cursor == nil { loadError = AppError.from(error).message }
        }
    }

    private func report(_ error: any Error) {
        let error = AppError.from(error)
        if error == .sessionExpired { session.sessionExpired() }
        errorMessage = error.message
    }
}
