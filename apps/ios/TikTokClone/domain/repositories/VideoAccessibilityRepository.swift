import Foundation

// Texte alternatif d'une vidéo (ADR-076), changé par son auteur après la publication.
protocol VideoAltTextRepository: Sendable {
    func setAltText(videoID: String, altText: String?) async throws
}

// Description automatique d'une image sur l'iPhone (ADR-076) : rien n'est envoyé.
protocol ImageDescriber: Sendable {
    func analyze(imageAt url: URL) async throws -> ImageAnalysis
}
