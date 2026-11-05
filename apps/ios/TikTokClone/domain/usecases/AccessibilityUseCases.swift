import Foundation

// Texte alternatif de sa vidéo (ADR-076) : nettoyé comme l'API ; vide = retiré.
struct SetVideoAltTextUseCase: Sendable {
    let videos: any VideoAltTextRepository

    /// Renvoie le texte enregistré (nil : retiré).
    func callAsFunction(videoID: String, altText: String?) async throws -> String? {
        let cleaned = AltTextRules.cleaned(altText)
        if let cleaned, cleaned.count > AltTextRules.maxLength {
            throw AppError.rejected("Le texte alternatif fait \(AltTextRules.maxLength) caractères au plus.")
        }
        try await videos.setAltText(videoID: videoID, altText: cleaned)
        return cleaned
    }
}

// Description automatique d'une vidéo d'après sa miniature (ADR-076) ; nil s'il n'y a rien à dire.
struct DescribeImageUseCase: Sendable {
    let describer: any ImageDescriber

    func callAsFunction(imageAt url: URL) async -> String? {
        guard let analysis = try? await describer.analyze(imageAt: url) else { return nil }
        return AutoDescription.text(analysis)
    }
}
