// Port du feed principal (ADR-016).
protocol FeedRepository: Sendable {
    // Sans curseur : nouvelle session, nouvel ordre.
    func page(cursor: String?) async throws -> FeedPage
    // Feed des abonnements (ADR-048), compte connecté : du plus récent au plus ancien, `nextCursor` nil à la fin.
    // Lève AppError.sessionExpired si la session n'est plus valide.
    func followingPage(cursor: String?) async throws -> FeedPage
    // Une vidéo publiée seule (lien d'app, notification…). Lève AppError.notFound si elle n'est plus publiée.
    func video(id: String) async throws -> FeedVideo
}

// Port de l'historique de visionnage : une vue par compte connecté (l'app n'appelle pas en invité).
protocol ViewHistoryRepository: Sendable {
    func recordView(videoID: String) async throws
}

// Source de pages de vidéos pour le lecteur vertical : le feed, ou une liste (grille d'un profil, historique).
protocol VideoPageSource: Sendable {
    func page(cursor: String?) async throws -> FeedPage
}
