import Foundation
import TikTokAPI

// Interactions par l'API (module interactions). Codes traduits en erreurs du domaine :
// 401 → session expirée, 403 → blocage, 404 → contenu disparu, 400 → message de l'API, 429 → limite (ADR-039).
struct RemoteInteractionRepository: InteractionRepository {
    static let commentsPageSize = 20

    let client: Client

    func setReaction(_ kind: ReactionKind, videoID: String, active: Bool) async throws -> InteractionState {
        switch (kind, active) {
        case (.like, true):
            switch try await call({ try await client.likeVideo(path: .init(id: videoID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .tooManyRequests(let error): throw AppError.tooManyActions(.reactions, retryAfter: max(1, error.headers.retryAfter ?? 60))
            case .unauthorized: throw AppError.sessionExpired
            case .forbidden: throw AppError.blocked
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case (.like, false):
            switch try await call({ try await client.unlikeVideo(path: .init(id: videoID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .unauthorized: throw AppError.sessionExpired
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case (.favorite, true):
            switch try await call({ try await client.favoriteVideo(path: .init(id: videoID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .tooManyRequests(let error): throw AppError.tooManyActions(.reactions, retryAfter: max(1, error.headers.retryAfter ?? 60))
            case .unauthorized: throw AppError.sessionExpired
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case (.favorite, false):
            switch try await call({ try await client.unfavoriteVideo(path: .init(id: videoID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .unauthorized: throw AppError.sessionExpired
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case (.repost, true):
            switch try await call({ try await client.repostVideo(path: .init(id: videoID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .tooManyRequests(let error): throw AppError.tooManyActions(.reactions, retryAfter: max(1, error.headers.retryAfter ?? 60))
            case .unauthorized: throw AppError.sessionExpired
            case .forbidden: throw AppError.blocked
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case (.repost, false):
            switch try await call({ try await client.unrepostVideo(path: .init(id: videoID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .unauthorized: throw AppError.sessionExpired
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        }
    }

    func setFollow(username: String, active: Bool) async throws -> InteractionState {
        if active {
            switch try await call({ try await client.followUser(path: .init(username: username)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .tooManyRequests(let error): throw AppError.tooManyActions(.follows, retryAfter: max(1, error.headers.retryAfter ?? 60))
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .unauthorized: throw AppError.sessionExpired
            case .forbidden: throw AppError.blocked
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        }
        switch try await call({ try await client.unfollowUser(path: .init(username: username)) }) {
        case .ok(let ok): return InteractionState(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func recordShare(videoID: String) async throws -> Int {
        switch try await call({ try await client.shareVideo(path: .init(id: videoID)) }) {
        case .ok(let ok): return try ok.body.json.sharesCount
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func comments(videoID: String, cursor: String?) async throws -> CommentPage {
        let output = try await call {
            try await client.listComments(path: .init(id: videoID), query: .init(cursor: cursor, limit: Self.commentsPageSize))
        }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return CommentPage(comments: page.items.map(VideoComment.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func replies(commentID: String, cursor: String?) async throws -> CommentPage {
        let output = try await call {
            try await client.listReplies(path: .init(id: commentID), query: .init(cursor: cursor, limit: Self.commentsPageSize))
        }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return CommentPage(comments: page.items.map(VideoComment.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func setCommentLike(commentID: String, active: Bool) async throws -> InteractionState {
        if active {
            switch try await call({ try await client.likeComment(path: .init(id: commentID)) }) {
            case .ok(let ok): return InteractionState(try ok.body.json)
            case .tooManyRequests(let error): throw AppError.tooManyActions(.reactions, retryAfter: max(1, error.headers.retryAfter ?? 60))
            case .unauthorized: throw AppError.sessionExpired
            case .forbidden: throw AppError.blocked
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        }
        switch try await call({ try await client.unlikeComment(path: .init(id: commentID)) }) {
        case .ok(let ok): return InteractionState(try ok.body.json)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func addComment(videoID: String, content: String, replyToID: String?) async throws -> VideoComment {
        let body = Components.Schemas.CreateCommentRequest(content: content, replyToId: replyToID)
        switch try await call({ try await client.addComment(path: .init(id: videoID), body: .json(body)) }) {
        case .created(let created): return VideoComment(try created.body.json)
        case .tooManyRequests(let error): throw AppError.tooManyActions(.comments, retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .forbidden: throw AppError.blocked
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteComment(id: String) async throws {
        switch try await call({ try await client.deleteComment(path: .init(id: id)) }) {
        case .noContent: return
        case .unauthorized: throw AppError.sessionExpired
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        // Déjà supprimé : le résultat voulu est atteint.
        case .notFound: return
        case .undocumented: throw AppError.unexpected
        }
    }

    func myComments(cursor: String?) async throws -> CommentHistoryPage {
        switch try await call({ try await client.listMyComments(query: .init(cursor: cursor, limit: Self.commentsPageSize)) }) {
        case .ok(let ok):
            let page = try ok.body.json
            return CommentHistoryPage(entries: page.items.map(CommentHistoryEntry.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    private func call<T>(_ operation: () async throws -> T) async throws -> T {
        try await mappingErrors(operation)
    }
}

extension InteractionState {
    init(_ dto: Components.Schemas.InteractionStateResponse) {
        self.init(active: dto.active, count: dto.count)
    }
}

extension VideoComment {
    init(_ dto: Components.Schemas.CommentResponse) {
        self.init(
            id: dto.id, videoID: dto.videoId, parentID: dto.parentId, content: dto.content, createdAt: dto.createdAt, author: UserSummary(dto.author),
            repliesCount: dto.repliesCount, likesCount: dto.likesCount, likedByAuthor: dto.likedByAuthor, viewerLiked: dto.viewer?.liked)
    }
}

extension CommentHistoryEntry {
    init(_ dto: Components.Schemas.CommentHistoryItemResponse) {
        self.init(
            id: dto.id,
            content: dto.content,
            createdAt: dto.createdAt,
            video: Video(id: dto.video.id, thumbnailURL: URL(string: dto.video.thumbnailUrl), author: UserSummary(dto.video.author))
        )
    }
}
