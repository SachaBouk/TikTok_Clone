import CoreGraphics
import Foundation

// Galerie maison de la création (ADR-062) : albums, vidéos et photos de l'appareil, miniatures, et fichiers à publier.
// Port (ADR-002) ; l'implémentation (data/media) s'appuie sur PhotoKit, avec l'autorisation d'accès aux Photos.

enum MediaLibraryAccess: Equatable, Sendable {
    case notDetermined
    case full
    // Accès à une partie des photos, choisie par l'utilisateur.
    case limited
    case denied

    var canRead: Bool { self == .full || self == .limited }
}

// Vidéo ou photo de la galerie.
struct LibraryAsset: Identifiable, Hashable, Sendable {
    let id: String
    let isVideo: Bool
    // Vidéos seulement.
    let duration: Duration?
}

// Album ; `nil` désigne « Récents » (toute la galerie).
struct LibraryAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
}

// Onglets de la galerie.
enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case videos
    case photos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tout"
        case .videos: "Vidéos"
        case .photos: "Photos"
        }
    }
}

protocol MediaLibrary: Sendable {
    func access() -> MediaLibraryAccess
    // Demande l'autorisation si elle n'a pas encore été donnée.
    func requestAccess() async -> MediaLibraryAccess
    // Albums non vides de l'utilisateur et du système (favoris, vidéos…), « Récents » non compris.
    func albums() async -> [LibraryAlbum]
    // Du plus récent au plus ancien.
    func assets(in album: LibraryAlbum?, filter: LibraryFilter) async -> [LibraryAsset]
    // Miniature carrée d'environ `side` pixels de côté (orientation appliquée).
    func thumbnail(of asset: LibraryAsset, side: Double) async -> CGImage?
    // Copie temporaire du fichier d'origine de la vidéo, téléchargée d'iCloud au besoin (métadonnées retirées ensuite,
    // ADR-035).
    func exportVideo(_ asset: LibraryAsset) async throws -> URL
    // Données de la photo (story), préparées ensuite (recadrage, réencodage sans métadonnées, ADR-051).
    func photoData(_ asset: LibraryAsset) async throws -> Data
}
