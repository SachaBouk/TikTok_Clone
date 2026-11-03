import Foundation

// « Télécharger » du menu d'une vidéo (ADR-067) : autorisation « ajout dans Photos », lien signé, téléchargement du
// fichier d'origine, puis enregistrement dans Photos. Le fichier temporaire est toujours supprimé.
struct DownloadVideoUseCase: Sendable {
    let links: any VideoDownloadRepository
    let files: any FileDownloader
    let photos: any PhotoLibrarySaver

    static let photosDenied = "Autorise l’ajout dans Photos dans les Réglages pour enregistrer des vidéos."

    func callAsFunction(videoID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard await photos.requestAddAccess() else { throw AppError.rejected(Self.photosDenied) }
        let link = try await links.downloadLink(videoID: videoID)
        let file = try await files.download(link.url, fileName: link.fileName, progress: progress)
        defer { try? FileManager.default.removeItem(at: file) }
        try await photos.saveVideo(file)
    }
}
