import Foundation

// Port des sons repris des vidéos (ADR-064), côté API (module feed), et de leur fichier.
protocol SoundRepository: Sendable {
    func recommended(cursor: String?) async throws -> SoundPage
    func favorites(cursor: String?) async throws -> SoundPage
    func search(_ text: String, cursor: String?) async throws -> SoundPage
    // Sons demandés (« Récents »), dans l'ordre ; un son qui n'est plus proposé est omis.
    func sounds(ids: [String]) async throws -> [Sound]
    // `.notFound` : le son n'est plus proposé.
    func setFavorite(_ favorite: Bool, soundID: String) async throws
    // Fichier du son, téléchargé (gardé pendant la session de l'app).
    func download(_ sound: Sound) async throws -> URL
}
