// Port du feed principal (ADR-016).
protocol FeedRepository: Sendable {
    // Sans curseur : nouvelle session, nouvel ordre.
    func page(cursor: String?) async throws -> FeedPage
    // Une vidéo publiée seule (lien d'app, notification…). Lève AppError.notFound si elle n'est plus publiée.
    func video(id: String) async throws -> FeedVideo
}

// Port de l'historique de visionnage : une vue par compte connecté (l'app n'appelle pas en invité).
protocol ViewHistoryRepository: Sendable {
    func recordView(videoID: String) async throws
}
