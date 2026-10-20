import Foundation

// Publication d'une vidéo depuis la galerie (ADR-016), par upload direct au stockage (ADR-007) :
// l'app demande une URL signée par partie, envoie les parties elle-même, puis confirme ; l'API lance le
// transcodage (ADR-008) et prévient l'app par WebSocket (`videoProcessed`, ADR-011).

// Statut d'une vidéo côté API (pipeline vidéo).
enum VideoStatus: String, Codable, Equatable, Sendable {
    case uploading
    case processing
    case ready
    case failed
}

// Visibilité d'une vidéo (ADR-061) : publique, ou privée (« Toi uniquement »), visible de son seul auteur.
enum VideoVisibility: String, Codable, CaseIterable, Equatable, Sendable {
    case everyone = "public"
    case onlyMe = "private"

    // « Qui peut regarder ta vidéo ».
    var label: String {
        switch self {
        case .everyone: "Tout le monde"
        case .onlyMe: "Toi uniquement"
        }
    }
}

// Vidéo (ou story, ADR-051) du compte connecté, suivie de l'envoi à la publication. La miniature n'existe qu'une fois
// `ready` ; une story n'a pas de description.
struct OwnVideo: Identifiable, Equatable, Sendable {
    let id: String
    let description: String?
    let status: VideoStatus
    let thumbnailURL: URL?
    let createdAt: Date
}

// Formats acceptés par l'API (`upload-rules.ts`, `stories/domain/story.ts`) : vidéos de la galerie iOS, et photo JPEG
// préparée par l'app pour une story (ADR-051).
enum MediaContentType: String, Codable, Equatable, Sendable, CaseIterable {
    case mp4 = "video/mp4"
    case quickTime = "video/quicktime"
    case jpeg = "image/jpeg"

    // D'après l'extension du fichier ; nil si le format n'est pas accepté.
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "mp4", "m4v": self = .mp4
        case "mov", "qt": self = .quickTime
        case "jpg", "jpeg": self = .jpeg
        default: return nil
        }
    }

    var isVideo: Bool { self != .jpeg }
}

// Ce qu'on publie : une vidéo du feed, ou une story (ADR-051). Même envoi multipart, routes différentes.
enum PublicationKind: String, Codable, Equatable, Sendable {
    case video
    case story
}

// Lieu d'une publication (ADR-065) : nom et adresse affichée, jamais de coordonnées.
struct VideoLocation: Codable, Hashable, Sendable {
    let name: String
    var address: String?
}

// Réglages de l'écran de publication ajoutés par l'ADR-065 : étiquette « Contenu généré par l'IA », lieu, couverture choisie
// (JPEG 9:16, déplacée dans le stockage des envois).
struct PublicationExtras: Equatable, Sendable {
    var aiGenerated = false
    var location: VideoLocation?
    var cover: URL?
}

// Ce que l'API reçoit en plus à la création de l'envoi (ADR-065) : `coverSize` demande une URL pour la couverture.
struct UploadExtras: Equatable, Sendable {
    var aiGenerated = false
    var location: VideoLocation?
    var coverSize: Int?
}

// Réponse à la demande d'upload : une URL signée par partie, valable jusqu'à `expiresAt` (2 h).
struct UploadTicket: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable {
        let number: Int
        let url: URL
    }

    // Vidéo, ou story pour une publication de story (ADR-051).
    let videoID: String
    let partSize: Int
    let parts: [Part]
    let expiresAt: Date
    // Couverture demandée (ADR-065) : un seul PUT du JPEG, `Content-Type: image/jpeg`.
    var coverURL: URL?
}

// Partie reçue par le stockage : son numéro et l'en-tête `ETag` de la réponse au PUT, tel quel.
struct UploadedPart: Codable, Equatable, Sendable {
    let number: Int
    let etag: String
}

// Envoi en cours, enregistré sur l'appareil après chaque étape (choix du développeur : reprise après relance).
// Le fichier est copié dans le stockage local des envois ; il est supprimé une fois l'envoi confirmé.
struct PendingUpload: Codable, Identifiable, Equatable, Sendable {
    let id: String
    // Compte qui publie : un envoi ne reprend que pour lui.
    let userID: String
    let fileName: String
    let contentType: MediaContentType
    let fileSize: Int
    let description: String?
    let createdAt: Date
    // Nil tant que l'API n'a pas créé la vidéo, ou après un abandon (URLs expirées) : il faut en redemander.
    var ticket: UploadTicket?
    // Parties déjà reçues par le stockage, par numéro : jamais renvoyées.
    var sentParts: [Int: String] = [:]
    var kind: PublicationKind = .video
    // Choisie à la publication (ADR-061) ; une story est toujours publique.
    var visibility: VideoVisibility = .everyone
    // « Autoriser les commentaires » (ADR-062) ; une story n'en a pas.
    var commentsEnabled = true
    // « Autoriser l'utilisation de mon son » et son repris d'une autre vidéo (ADR-064).
    var soundShared = true
    var soundID: String?
    // ADR-065 : étiquette IA, lieu, couverture (fichier du stockage des envois, envoyée ou non).
    var aiGenerated = false
    var location: VideoLocation?
    var coverFileName: String?
    var coverSize: Int?
    var coverSent = false

    // Octets déjà reçus par le stockage.
    var sentBytes: Int {
        guard let ticket else { return 0 }
        return sentParts.keys.reduce(0) { total, number in
            total + UploadRules.range(ofPart: number, partSize: ticket.partSize, fileSize: fileSize).count
        }
    }

    var progress: Double {
        fileSize > 0 ? Double(sentBytes) / Double(fileSize) : 0
    }
}

extension PendingUpload {
    private enum CodingKeys: String, CodingKey {
        case id, userID, fileName, contentType, fileSize, description, createdAt, ticket, sentParts, kind, visibility, commentsEnabled
        case soundShared, soundID, aiGenerated, location, coverFileName, coverSize, coverSent
    }

    // Un envoi enregistré avant les stories n'a pas de `kind` : c'est une vidéo ; avant les vidéos privées, pas de
    // `visibility` : elle est publique ; avant l'ADR-062, pas de `commentsEnabled` : ils sont autorisés ; avant l'ADR-064, son
    // partagé, sans son repris ; avant l'ADR-065, sans étiquette IA, lieu ni couverture.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            userID: try container.decode(String.self, forKey: .userID),
            fileName: try container.decode(String.self, forKey: .fileName),
            contentType: try container.decode(MediaContentType.self, forKey: .contentType),
            fileSize: try container.decode(Int.self, forKey: .fileSize),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            ticket: try container.decodeIfPresent(UploadTicket.self, forKey: .ticket),
            sentParts: try container.decodeIfPresent([Int: String].self, forKey: .sentParts) ?? [:],
            kind: try container.decodeIfPresent(PublicationKind.self, forKey: .kind) ?? .video,
            visibility: try container.decodeIfPresent(VideoVisibility.self, forKey: .visibility) ?? .everyone,
            commentsEnabled: try container.decodeIfPresent(Bool.self, forKey: .commentsEnabled) ?? true,
            soundShared: try container.decodeIfPresent(Bool.self, forKey: .soundShared) ?? true,
            soundID: try container.decodeIfPresent(String.self, forKey: .soundID),
            aiGenerated: try container.decodeIfPresent(Bool.self, forKey: .aiGenerated) ?? false,
            location: try container.decodeIfPresent(VideoLocation.self, forKey: .location),
            coverFileName: try container.decodeIfPresent(String.self, forKey: .coverFileName),
            coverSize: try container.decodeIfPresent(Int.self, forKey: .coverSize),
            coverSent: try container.decodeIfPresent(Bool.self, forKey: .coverSent) ?? false
        )
    }
}

// Règles de l'upload, alignées sur celles de l'API (`apps/api/src/modules/videos/domain/upload-rules.ts`).
enum UploadRules {
    static let maxFileSize = 1024 * 1024 * 1024  // 1 Gio
    static let maxDescriptionLength = 2200
    // Couverture choisie (ADR-065) : un JPEG de 2 Mio au plus ; lieu : longueurs de l'API.
    static let maxCoverFileSize = 2 * 1024 * 1024
    static let maxLocationNameLength = 100
    static let maxLocationAddressLength = 200
    // Durée maximale (ADR-040), comme le worker : 3 minutes, à une seconde près (arrondis du conteneur).
    static let maxDuration: Duration = .seconds(180)
    static let durationTolerance: Duration = .seconds(1)
    // Un envoi jamais terminé est oublié au bout de ce délai : l'API supprime alors la vidéo (maintenance).
    static let abandonedAfter: TimeInterval = 24 * 60 * 60
    // Marge avant l'expiration des URLs signées : au-delà, un envoi neuf est demandé.
    static let ticketExpiryMargin: TimeInterval = 60

    // Octets de la partie `number` (à partir de 1) ; la dernière peut être plus courte.
    static func range(ofPart number: Int, partSize: Int, fileSize: Int) -> Range<Int> {
        let start = min((number - 1) * partSize, fileSize)
        return start..<min(start + partSize, fileSize)
    }

    static func isTooLong(_ duration: Duration) -> Bool {
        duration > maxDuration + durationTolerance
    }

    // Description nettoyée ; nil si vide.
    static func sanitizedDescription(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isExpired(_ ticket: UploadTicket, at now: Date) -> Bool {
        now >= ticket.expiresAt.addingTimeInterval(-ticketExpiryMargin)
    }

    static func isAbandoned(_ upload: PendingUpload, at now: Date) -> Bool {
        now.timeIntervalSince(upload.createdAt) >= abandonedAfter
    }
}

// Audience par défaut des publications (« Définir comme audience par défaut », ADR-062) : gardée sur l'iPhone.
protocol PublishingPreferences: Sendable {
    var defaultVisibility: VideoVisibility { get }
    func setDefaultVisibility(_ visibility: VideoVisibility)
    // « Enregistrer sur l'appareil » (ADR-065), coupé par défaut.
    var saveToDevice: Bool { get }
    func setSaveToDevice(_ enabled: Bool)
}
