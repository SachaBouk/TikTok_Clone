import Foundation
import Synchronization

@testable import TikTokClone

// Interactions en mémoire : garde les appels et renvoie des états comme l'API (compteurs relus côté serveur).
final class FakeInteractionRepository: InteractionRepository {
    struct State {
        var counts: [String: Int] = [:]
        var calls: [String] = []
        var error: AppError?
        var comments: [String: [VideoComment]] = [:]
        var shares = 0
        var followers = 10
        var delay: Duration = .zero
        var myComments: [CommentHistoryEntry] = []
        // Réponses par commentaire d'origine, de la plus ancienne à la plus récente (ADR-060).
        var replies: [String: [VideoComment]] = [:]
    }

    let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }
    func setServerCount(_ count: Int, for key: String) { state.withLock { $0.counts[key] = count } }

    func setReaction(_ kind: ReactionKind, videoID: String, active: Bool) async throws -> InteractionState {
        let delay = state.withLock { $0.delay }
        if delay > .zero { try await Task.sleep(for: delay) }
        return try state.withLock { state in
            state.calls.append("\(kind)-\(videoID)-\(active)")
            if let error = state.error { throw error }
            let key = "\(kind)-\(videoID)"
            let count = max(0, (state.counts[key] ?? 0) + (active ? 1 : -1))
            state.counts[key] = count
            return InteractionState(active: active, count: count)
        }
    }

    func setFollow(username: String, active: Bool) async throws -> InteractionState {
        try state.withLock { state in
            state.calls.append("follow-\(username)-\(active)")
            if let error = state.error { throw error }
            state.followers += active ? 1 : -1
            return InteractionState(active: active, count: state.followers)
        }
    }

    func recordShare(videoID: String) async throws -> Int {
        try state.withLock { state in
            state.calls.append("share-\(videoID)")
            if let error = state.error { throw error }
            state.shares += 1
            return state.shares
        }
    }

    func comments(videoID: String, cursor: String?) async throws -> CommentPage {
        try state.withLock { state in
            if let error = state.error { throw error }
            let all = state.comments[videoID] ?? []
            let start = cursor.flatMap { c in all.firstIndex { $0.id == c }.map { $0 + 1 } } ?? 0
            let page = Array(all.dropFirst(start).prefix(2))
            let next = start + 2 < all.count ? page.last?.id : nil
            return CommentPage(comments: page, nextCursor: next)
        }
    }

    func replies(commentID: String, cursor: String?) async throws -> CommentPage {
        try state.withLock { state in
            state.calls.append("replies-\(commentID)-\(cursor ?? "")")
            if let error = state.error { throw error }
            let all = state.replies[commentID] ?? []
            let start = cursor.flatMap { c in all.firstIndex { $0.id == c }.map { $0 + 1 } } ?? 0
            let page = Array(all.dropFirst(start).prefix(2))
            let next = start + 2 < all.count ? page.last?.id : nil
            return CommentPage(comments: page, nextCursor: next)
        }
    }

    // Une réponse est rangée sous le commentaire d'origine, comme l'API.
    func addComment(videoID: String, content: String, replyToID: String?) async throws -> VideoComment {
        try state.withLock { state in
            state.calls.append("comment-\(videoID)-\(content)" + (replyToID.map { "-reply-\($0)" } ?? ""))
            if let error = state.error { throw error }
            var comment = VideoComment.sample("new-\(state.calls.count)", videoID: videoID, content: content, author: .alice)
            if let replyToID {
                let parent = state.replies.first { $0.value.contains { $0.id == replyToID } }?.key ?? replyToID
                comment.parentID = parent
                state.replies[parent, default: []].append(comment)
            } else {
                state.comments[videoID, default: []].insert(comment, at: 0)
            }
            return comment
        }
    }

    func setCommentLike(commentID: String, active: Bool) async throws -> InteractionState {
        try state.withLock { state in
            state.calls.append("\(active ? "like" : "unlike")-comment-\(commentID)")
            if let error = state.error { throw error }
            let key = "comment-\(commentID)"
            let count = max(0, (state.counts[key] ?? 0) + (active ? 1 : -1))
            state.counts[key] = count
            return InteractionState(active: active, count: count)
        }
    }

    func myComments(cursor: String?) async throws -> CommentHistoryPage {
        try state.withLock { state in
            if let error = state.error { throw error }
            return CommentHistoryPage(entries: state.myComments, nextCursor: nil)
        }
    }

    func deleteComment(id: String) async throws {
        try state.withLock { state in
            state.calls.append("delete-\(id)")
            if let error = state.error { throw error }
        }
    }
}

extension UserSummary {
    static let alice = UserSummary(id: UserProfile.alice.id, username: "alice", displayName: "Alice", avatarURL: nil)
    static let bob = UserSummary(id: "bob-id", username: "bob", displayName: "Bob", avatarURL: nil)
}

extension VideoComment {
    static func sample(_ id: String, videoID: String = "v1", content: String = "Super", author: UserSummary = .bob) -> VideoComment {
        VideoComment(id: id, videoID: videoID, content: content, createdAt: Date(timeIntervalSince1970: 1_800_000_000), author: author)
    }
}
