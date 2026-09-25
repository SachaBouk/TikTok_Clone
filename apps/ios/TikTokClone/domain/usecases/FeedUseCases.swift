struct LoadFeedPageUseCase: Sendable {
    let feed: any FeedRepository

    func callAsFunction(cursor: String?) async throws -> FeedPage {
        try await feed.page(cursor: cursor)
    }
}

struct RecordViewUseCase: Sendable {
    let history: any ViewHistoryRepository

    func callAsFunction(videoID: String) async throws {
        try await history.recordView(videoID: videoID)
    }
}
