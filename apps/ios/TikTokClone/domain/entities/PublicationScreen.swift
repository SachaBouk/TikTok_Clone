import Foundation

// Écran de publication (ADR-065) : couverture, lieu, brouillons. Règles pures, testées sans UIKit.

// Style du titre de la couverture, comme TikTok (sans son logo).
enum CoverTitleStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case vector
    case glitch
    case tint
    case retro
    case skew
    case pill
    case pop
    case bubble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .vector: "Vecteur"
        case .glitch: "Glitch"
        case .tint: "Teinte"
        case .retro: "Rétro"
        case .skew: "Incliné"
        case .pill: "Pilule"
        case .pop: "Pop"
        case .bubble: "Bulle"
        }
    }
}

// Couverture : une image de la vidéo finale (`time`) et, au choix, un titre dans un style. Sans changement, la miniature
// vient du worker (image de la vidéo).
struct CoverChoice: Codable, Equatable, Sendable {
    static let maxTitleLength = 60
    // Images proposées sur la frise.
    static let frameCount = 10

    var time: Duration = .zero
    var style: CoverTitleStyle?
    private(set) var title = ""

    // Titre affiché : un style choisi et du texte.
    var shownTitle: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return style != nil && !trimmed.isEmpty ? trimmed : nil
    }

    // Couverture choisie : une autre image que la première, ou un titre.
    var isCustom: Bool { time != .zero || shownTitle != nil }

    // Texte du titre, borné à 60 caractères, sur une seule ligne.
    mutating func setTitle(_ text: String) {
        title = String(text.replacingOccurrences(of: "\n", with: " ").prefix(Self.maxTitleLength))
    }

    // Instant ramené dans la vidéo (après une nouvelle édition qui l'a raccourcie).
    func clamped(to duration: Duration) -> CoverChoice {
        var choice = self
        choice.time = min(max(.zero, time), max(.zero, duration - .milliseconds(100)))
        return choice
    }

    // Instants des images de la frise, répartis sur la vidéo (la première à 0).
    static func frameTimes(duration: Duration, count: Int = frameCount) -> [Duration] {
        guard count > 0, duration > .zero else { return [.zero] }
        return (0..<count).map { duration * (Double($0) / Double(count)) }
    }

    // Instant à une position de la frise (0 à 1).
    static func time(atFraction fraction: Double, duration: Duration) -> Duration {
        duration * min(max(fraction, 0), 0.999)
    }
}

// Accès à la localisation pour les lieux à proximité (ADR-065).
enum LocationAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

// Lieu proposé par la recherche ou à proximité : `id` stable pour les listes.
extension VideoLocation: Identifiable {
    var id: String { "\(name)|\(address ?? "")" }

    // Nom et adresse ramenés aux longueurs de l'API.
    var bounded: VideoLocation {
        VideoLocation(
            name: String(name.prefix(UploadRules.maxLocationNameLength)),
            address: address.map { String($0.prefix(UploadRules.maxLocationAddressLength)) }.flatMap { $0.isEmpty ? nil : $0 })
    }
}

// Brouillon enregistré sur l'iPhone (ADR-065) : plan d'édition (fichiers compris), texte et réglages de la publication.
struct VideoDraft: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userID: String
    var savedAt: Date
    var plan: EditPlan
    var source: MediaSource
    var description: String
    var visibility: VideoVisibility
    var commentsEnabled: Bool
    var soundShared: Bool
    var aiGenerated: Bool
    var location: VideoLocation?
    var cover: CoverChoice

    var duration: Duration { plan.outputDuration }
}

// Port des brouillons (ADR-065) : enregistrés sur l'iPhone avec leurs fichiers, jamais envoyés.
protocol DraftStore: Sendable {
    // Brouillons du compte, du plus récent au plus ancien.
    func all(userID: String) -> [VideoDraft]
    // Déplace les fichiers du plan dans le brouillon et l'enregistre, avec son image (JPEG).
    func save(_ draft: VideoDraft, thumbnail: Data?) throws -> VideoDraft
    // Ouvrir : les fichiers ressortent du brouillon (dossier temporaire), qui est supprimé. Renvoie le plan déplacé.
    func open(_ draft: VideoDraft) throws -> VideoDraft
    func delete(_ draft: VideoDraft)
    // Tous les brouillons, de tous les comptes (changement de session).
    func deleteAll()
    func thumbnailURL(of draft: VideoDraft) -> URL?
}

// Port de la recherche de lieux (ADR-065) : Apple Plans, sans jamais renvoyer de coordonnées.
@MainActor
protocol PlaceSearch: AnyObject {
    var locationAccess: LocationAccess { get }
    func requestLocationAccess() async -> LocationAccess
    func search(_ text: String) async throws -> [VideoLocation]
    // Lieux autour de la position (localisation autorisée seulement).
    func nearby() async throws -> [VideoLocation]
}

// Port de l'enregistrement dans Photos (ADR-065, « ajout seulement »).
protocol PhotoLibrarySaver: Sendable {
    func requestAddAccess() async -> Bool
    func saveVideo(_ file: URL) async throws
}
