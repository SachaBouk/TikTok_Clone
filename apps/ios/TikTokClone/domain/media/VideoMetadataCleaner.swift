import Foundation

// Port (ADR-002) : retire d'une vidéo locale les métadonnées personnelles (position GPS, appareil…), avant
// qu'elle ne quitte le téléphone. L'implémentation (data/media) s'appuie sur AVFoundation, sans réencodage.
protocol VideoMetadataCleaner: Sendable {
    // Renvoie un nouveau fichier sans ces métadonnées. Le fichier reçu est supprimé, que le nettoyage réussisse ou non.
    func clean(_ file: URL) async throws -> URL
}
