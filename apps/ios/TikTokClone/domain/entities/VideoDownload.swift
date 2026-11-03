import Foundation

// Téléchargement d'une vidéo (ADR-067) : l'API renvoie une URL signée du fichier d'origine, valable 15 min.
struct VideoDownloadLink: Equatable, Sendable {
    let url: URL
    let fileName: String
    // Taille du fichier, en octets.
    let size: Int
}

// Port : lien de téléchargement d'une vidéo. Refus de l'auteur (403), vidéo masquée (404), limite (429).
protocol VideoDownloadRepository: Sendable {
    func downloadLink(videoID: String) async throws -> VideoDownloadLink
}

// Port : téléchargement d'un fichier dans un dossier temporaire, avec sa progression (0 à 1).
protocol FileDownloader: Sendable {
    func download(_ url: URL, fileName: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}
