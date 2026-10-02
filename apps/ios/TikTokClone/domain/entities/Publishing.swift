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

// Vidéo du compte connecté, suivie de l'envoi à la publication. La miniature n'existe qu'une fois `ready`.
struct OwnVideo: Identifiable, Equatable, Sendable {
    let id: String
    let description: String?
    let status: VideoStatus
    let thumbnailURL: URL?
    let createdAt: Date
}

// Formats acceptés par l'API (`upload-rules.ts`) : ceux que produit la galerie iOS.
enum VideoContentType: String, Codable, Equatable, Sendable, CaseIterable {
    case mp4 = "video/mp4"
    case quickTime = "video/quicktime"

    // D'après l'extension du fichier exporté par la galerie ; nil si le format n'est pas accepté.
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "mp4", "m4v": self = .mp4
        case "mov", "qt": self = .quickTime
        default: return nil
        }
    }
}

// Réponse à la demande d'upload : une URL signée par partie, valable jusqu'à `expiresAt` (2 h).
struct UploadTicket: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable {
        let number: Int
        let url: URL
    }

    let videoID: String
    let partSize: Int
    let parts: [Part]
    let expiresAt: Date
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
    let contentType: VideoContentType
    let fileSize: Int
    let description: String?
    let createdAt: Date
    // Nil tant que l'API n'a pas créé la vidéo, ou après un abandon (URLs expirées) : il faut en redemander.
    var ticket: UploadTicket?
    // Parties déjà reçues par le stockage, par numéro : jamais renvoyées.
    var sentParts: [Int: String] = [:]

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

// Règles de l'upload, alignées sur celles de l'API (`apps/api/src/modules/videos/domain/upload-rules.ts`).
enum UploadRules {
    static let maxFileSize = 1024 * 1024 * 1024  // 1 Gio
    static let maxDescriptionLength = 2200
    // Durée maximale (ADR-040), comme le worker : 3 minutes, à une seconde près (arrondis du conteneur).
    static let maxDuration: Duration = .seconds(180)
    static let durationTolerance: Duration = .seconds(1)
    static let tooLongMessage = "Cette vidéo dure plus de 3 minutes. Choisis-en une plus courte."
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
