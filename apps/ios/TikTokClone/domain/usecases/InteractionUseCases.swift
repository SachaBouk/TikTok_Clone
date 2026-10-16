// Cas d'usage des interactions (ADR-002). Les règles d'affichage optimiste sont dans la présentation ;
// ici, seulement ce qui part vers l'API.

struct SetReactionUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(_ kind: ReactionKind, videoID: String, active: Bool) async throws -> InteractionState {
        try await interactions.setReaction(kind, videoID: videoID, active: active)
    }
}

struct SetFollowUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(username: String, active: Bool) async throws -> InteractionState {
        try await interactions.setFollow(username: username, active: active)
    }
}

struct ShareVideoUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(videoID: String) async throws -> Int {
        try await interactions.recordShare(videoID: videoID)
    }
}

struct LoadCommentsUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(videoID: String, cursor: String?) async throws -> CommentPage {
        try await interactions.comments(videoID: videoID, cursor: cursor)
    }
}

struct LoadRepliesUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(commentID: String, cursor: String?) async throws -> CommentPage {
        try await interactions.replies(commentID: commentID, cursor: cursor)
    }
}

struct AddCommentUseCase: Sendable {
    let interactions: any InteractionRepository

    // Texte nettoyé ; vide ou de plus de 500 caractères : refusé sans appel à l'API. `replyTo` : réponse (ADR-060).
    func callAsFunction(videoID: String, text: String, replyTo: VideoComment? = nil) async throws -> VideoComment {
        guard let content = CommentRules.sanitized(text) else {
            throw AppError.rejected("Un commentaire fait de 1 à \(CommentRules.maxLength) caractères.")
        }
        return try await interactions.addComment(videoID: videoID, content: content, replyToID: replyTo?.id)
    }
}

struct SetCommentLikeUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(commentID: String, active: Bool) async throws -> InteractionState {
        try await interactions.setCommentLike(commentID: commentID, active: active)
    }
}

// Suggestions du bouton « @ » (ADR-060) : sans texte, ses abonnements ; sinon, la recherche de comptes (ADR-049).
struct MentionSuggestionsUseCase: Sendable {
    static let limit = 8
    let relationships: any RelationshipRepository
    let search: any SearchRepository

    func callAsFunction(prefix: String, username: String?) async throws -> [UserSummary] {
        if prefix.isEmpty {
            guard let username else { return [] }
            let page = try await relationships.follows(.following, username: username, cursor: nil)
            return Array(page.entries.map(\.user).prefix(Self.limit))
        }
        let page = try await search.searchAccounts(query: prefix, cursor: nil)
        return Array(page.results.map(\.user).prefix(Self.limit))
    }
}

struct DeleteCommentUseCase: Sendable {
    let interactions: any InteractionRepository

    func callAsFunction(id: String) async throws {
        try await interactions.deleteComment(id: id)
    }
}

struct LoadVideoUseCase: Sendable {
    let feed: any FeedRepository

    func callAsFunction(id: String) async throws -> FeedVideo {
        try await feed.video(id: id)
    }
}
