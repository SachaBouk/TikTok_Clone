import Foundation

// Collection de favoris (ADR-072) : nom, visibilité, nombre de vidéos, image (dernière vidéo visible), titulaire.
struct VideoCollection: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var visibility: VideoVisibility
    var videosCount: Int
    var coverURL: URL?
    let owner: UserSummary
    let createdAt: Date
    var updatedAt: Date
    // Feuille « Enregistrer dans la collection » : contient-elle la vidéo demandée ? nil hors de cette feuille.
    var containsVideo: Bool?

    var isPublic: Bool { visibility == .everyone }

    // « 11 publications », « 1 publication ».
    var countLabel: String { videosCount == 1 ? "1 publication" : "\(videosCount) publications" }
}

// Règles des collections, alignées sur l'API (`collections/domain/collection.ts`). L'API reste seule juge.
enum CollectionRules {
    static let maxNameLength = 30
    // Collections proposées par l'appui long sur le signet, avant « Plus ».
    static let recentCount = 3
    // Vidéos ajoutées en une fois (limite de l'API).
    static let maxBatch = 50

    // Nom nettoyé comme l'API (espaces réduits), ou nil s'il est vide ou trop long.
    static func cleanedName(_ name: String) -> String? {
        let cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty || cleaned.count > maxNameLength ? nil : cleaned
    }

    // Collections les plus récemment utilisées en premier (ordre de l'API), après un changement fait dans l'app.
    static func sorted(_ collections: [VideoCollection]) -> [VideoCollection] {
        collections.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id > $1.id }
    }
}

// Lien d'app vers une collection (ADR-072) : tiktokclone://collections/<id>.
enum CollectionLink {
    static func url(for id: String) -> URL {
        var components = URLComponents()
        components.scheme = VideoLink.scheme
        components.host = "collections"
        components.path = "/\(id)"
        return components.url!
    }

    // Identifiant de la collection, ou nil si le lien n'en est pas un.
    static func id(from url: URL) -> String? {
        guard url.scheme == VideoLink.scheme, url.host == "collections" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = parts.first, UUID(uuidString: id) != nil else { return nil }
        return id.lowercased()
    }
}
