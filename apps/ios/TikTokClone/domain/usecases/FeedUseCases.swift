struct LoadFeedPageUseCase: VideoPageSource {
    let feed: any FeedRepository

    func callAsFunction(cursor: String?) async throws -> FeedPage {
        try await feed.page(cursor: cursor)
    }

    func page(cursor: String?) async throws -> FeedPage {
        try await self(cursor: cursor)
    }
}

struct RecordViewUseCase: Sendable {
    let history: any ViewHistoryRepository

    func callAsFunction(videoID: String) async throws {
        try await history.recordView(videoID: videoID)
    }
}
