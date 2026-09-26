import Foundation

// Port des vidéos du compte connecté, côté API (module videos).
protocol VideoPublishingRepository: Sendable {
    // Crée la vidéo en `uploading` et renvoie une URL signée par partie. `.rejected` : format ou taille refusés.
    func createUpload(contentType: VideoContentType, fileSize: Int, description: String?) async throws -> UploadTicket
    // Assemble les parties et lance le transcodage : la vidéo passe en `processing`.
    // Lève UploadFailure.alreadyConfirmed si l'API l'a déjà fait (réponse perdue), .restartNeeded si l'envoi
    // est perdu (parties refusées, vidéo supprimée entre-temps).
    func completeUpload(videoID: String, parts: [UploadedPart]) async throws -> OwnVideo
    // `.notFound` : vidéo supprimée.
    func video(id: String) async throws -> OwnVideo
    // Vidéos en `processing` ou `failed`, de la plus récente à la plus ancienne.
    func pendingVideos() async throws -> [OwnVideo]
    // Quel que soit le statut, y compris pendant l'envoi. Déjà supprimée : sans erreur.
    func deleteVideo(id: String) async throws
}

// Port de l'envoi d'une partie au stockage objet, sur son URL signée (PUT direct, sans passer par l'API).
protocol UploadPartTransport: Sendable {
    // Renvoie l'en-tête `ETag` de la réponse. `sent` : octets de la partie déjà envoyés.
    // Lève AppError.network (coupure : réessayer) ou UploadFailure.restartNeeded (URL expirée ou refusée).
    func upload(_ data: Data, to url: URL, sent: @escaping @Sendable (Int) -> Void) async throws -> String
}

// Port du stockage local des envois (reprise après relance de l'app).
protocol UploadStore: Sendable {
    func all() -> [PendingUpload]
    func save(_ upload: PendingUpload) throws
    // Oublie l'envoi et supprime son fichier.
    func remove(_ upload: PendingUpload)
    func size(ofFileAt url: URL) throws -> Int
    // Déplace le fichier choisi dans le stockage des envois ; renvoie son nom.
    func adoptFile(at url: URL, id: String) throws -> String
    func fileURL(named fileName: String) -> URL
    func read(fileName: String, range: Range<Int>) throws -> Data
}

// Envoi à reprendre autrement qu'en réessayant la même étape.
enum UploadFailure: Error, Equatable, Sendable {
    // URLs expirées, parties refusées ou vidéo supprimée : l'envoi repart de zéro avec une nouvelle vidéo.
    case restartNeeded
    // L'API a déjà assemblé l'envoi (réponse à la confirmation perdue) : lire la vidéo.
    case alreadyConfirmed
}
