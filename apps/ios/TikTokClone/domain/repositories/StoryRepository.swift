import Foundation

// Port des stories (module stories de l'API, ADR-051).
protocol StoryRepository: Sendable {
    // Rangée du compte connecté : sa story, puis ses abonnements qui en ont une.
    func tray() async throws -> [StoryTrayEntry]
    // Stories actives d'un compte, de la plus ancienne à la plus récente ; vide s'il n'en a pas (ou s'il est masqué).
    func stories(username: String) async throws -> [Story]
    // À l'affichage d'une story d'un autre compte.
    func recordView(storyID: String) async throws
    func setLiked(storyID: String, liked: Bool) async throws
    // Personnes qui ont vu sa story, de la plus récente à la plus ancienne.
    func viewers(storyID: String, cursor: String?) async throws -> StoryViewersPage
}

// Port de la publication d'une story : même envoi multipart que les vidéos (ADR-007), routes du module stories.
protocol StoryPublishingRepository: Sendable {
    // Crée la story en `uploading` et renvoie une URL signée par partie. `.rejected` : format ou taille refusés,
    // `.tooManyActions(.stories, …)` : limite ; 30 stories actives au plus.
    func createUpload(contentType: MediaContentType, fileSize: Int) async throws -> UploadTicket
    // Photo : publiée (`ready`) ; vidéo : `processing`. Mêmes erreurs que pour une vidéo (`UploadFailure`).
    func completeUpload(storyID: String, parts: [UploadedPart]) async throws -> OwnVideo
    // `.notFound` : story supprimée ou expirée.
    func story(id: String) async throws -> OwnVideo
    // Quel que soit le statut. Déjà supprimée : sans erreur.
    func deleteStory(id: String) async throws
}

// Port de la préparation d'une photo de story : orientation appliquée, recadrée en 9:16, 1080×1920, réencodée en JPEG
// (sans EXIF ni position GPS, comme les vidéos, ADR-035). Renvoie le fichier temporaire produit.
protocol StoryPhotoRenderer: Sendable {
    func render(_ imageData: Data) async throws -> URL
}
