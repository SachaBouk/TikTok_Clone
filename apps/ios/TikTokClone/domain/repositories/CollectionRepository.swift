import Foundation

// Port des collections de favoris (module collections, ADR-072). `.notFound` : collection inconnue, à un autre compte ou
// privée ; `.rejected` : nom invalide, vidéo indisponible.
protocol CollectionRepository: Sendable {
    // Ses collections, de la plus récemment utilisée à la plus ancienne ; avec `videoID`, `containsVideo` est rempli.
    func myCollections(containing videoID: String?) async throws -> [VideoCollection]
    // Collections publiques d'un compte (toutes pour son titulaire).
    func profileCollections(username: String) async throws -> [VideoCollection]
    func collection(id: String) async throws -> VideoCollection
    func create(name: String, visibility: VideoVisibility, videoIDs: [String]) async throws -> VideoCollection
    func update(id: String, name: String?, visibility: VideoVisibility?) async throws -> VideoCollection
    func delete(id: String) async throws
    // Vidéos mises en favori si besoin, puis ajoutées (déjà présentes : ignorées).
    func add(videoIDs: [String], to id: String) async throws -> VideoCollection
    // Retirées de la collection, gardées en favoris.
    func remove(videoIDs: [String], from id: String) async throws -> VideoCollection
}
