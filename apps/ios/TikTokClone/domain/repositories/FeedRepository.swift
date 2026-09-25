// Port du feed principal (ADR-016).
protocol FeedRepository: Sendable {
    // Sans curseur : nouvelle session, nouvel ordre.
    func page(cursor: String?) async throws -> FeedPage
}

// Port de l'historique de visionnage : une vue par compte connecté (l'app n'appelle pas en invité).
protocol ViewHistoryRepository: Sendable {
    func recordView(videoID: String) async throws
}
