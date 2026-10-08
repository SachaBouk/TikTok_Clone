import CoreGraphics
import Foundation

// Enregistrement et édition vidéo dans l'app (ADR-052) : segments filmés par la caméra, puis plan d'édition (découpage,
// vitesse, filtre, textes) appliqué à l'export sur l'iPhone. Règles pures, testées sans AVFoundation (ADR-002).

// Origine du média publié (mesure d'audience).
enum MediaSource: String, Equatable, Sendable {
    case camera
    case gallery
}

// Fichier d'origine : segment filmé, ou vidéo de la galerie déjà nettoyée de ses métadonnées (ADR-035).
struct SourceClip: Equatable, Sendable {
    let file: URL
    let duration: Duration
}

// Durée maximale d'une publication : vidéo (ADR-040) ou story (ADR-051).
extension PublicationKind {
    var maxDuration: Duration {
        self == .story ? StoryRules.maxVideoDuration : UploadRules.maxDuration
    }

    // Comme le worker : à une seconde près (arrondis du conteneur).
    func isTooLong(_ duration: Duration) -> Bool {
        duration > maxDuration + UploadRules.durationTolerance
    }

    // Vidéo de la galerie trop longue : l'éditeur s'ouvre sur ce message.
    var tooLongSourceMessage: String {
        self == .story
            ? "Une story dure 60 secondes au plus : choisis le passage à garder."
            : "Cette vidéo dure plus de 3 minutes : choisis le passage à garder."
    }

    // Message de l'éditeur quand la vidéo finale dépasse la limite.
    var tooLongEditMessage: String {
        self == .story
            ? "Une story dure 60 secondes au plus. Raccourcis la vidéo."
            : "Une vidéo dure 3 minutes au plus. Raccourcis-la."
    }
}

// Enregistrement par segments (comme TikTok) : toucher pour démarrer, toucher pour arrêter, plusieurs segments mis bout à
// bout, le dernier peut être retiré. La durée totale est bornée par celle de la publication.
struct RecordingSession: Equatable, Sendable {
    // En deçà, un segment est ignoré (toucher trop bref) ; et il ne reste plus de quoi en filmer un.
    static let minSegmentDuration: Duration = .milliseconds(300)

    let maxDuration: Duration
    private(set) var segments: [SourceClip] = []

    init(kind: PublicationKind) {
        maxDuration = kind.maxDuration
    }

    var recordedDuration: Duration {
        segments.reduce(.zero) { $0 + $1.duration }
    }

    var remaining: Duration {
        max(.zero, maxDuration - recordedDuration)
    }

    var isFull: Bool {
        remaining < Self.minSegmentDuration
    }

    // Part de la durée maximale déjà filmée (0 à 1), en comptant le segment en cours.
    func progress(including current: Duration = .zero) -> Double {
        min(1, (recordedDuration + current) / maxDuration)
    }

    // Faux si le segment est trop bref : son fichier est alors à supprimer.
    @discardableResult
    mutating func append(_ segment: SourceClip) -> Bool {
        guard segment.duration >= Self.minSegmentDuration else { return false }
        segments.append(segment)
        return true
    }

    mutating func removeLast() -> SourceClip? {
        segments.popLast()
    }

    mutating func removeAll() -> [SourceClip] {
        defer { segments = [] }
        return segments
    }
}

// Vitesse de toute la vidéo ; la hauteur du son est gardée.
enum PlaybackSpeed: Double, CaseIterable, Identifiable, Equatable, Sendable {
    case half = 0.5
    case normal = 1
    case faster = 1.5
    case double = 2

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .half: "0,5×"
        case .normal: "1×"
        case .faster: "1,5×"
        case .double: "2×"
        }
    }
}

// Filtres de couleur (Core Image, dans l'adaptateur d'export) ; l'identifiant sert aussi à la mesure d'audience.
enum VideoFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case none
    case mono
    case warm
    case cool
    case vivid
    case vintage
    case fade
    case instant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Aucun"
        case .mono: "Noir et blanc"
        case .warm: "Chaud"
        case .cool: "Froid"
        case .vivid: "Vif"
        case .vintage: "Vintage"
        case .fade: "Fondu"
        case .instant: "Instantané"
        }
    }
}

// Texte posé sur la vidéo, visible pendant toute sa durée. Position du centre et taille relatives à l'image : le rendu
// est le même en aperçu et à l'export, quelle que soit la résolution.
struct TextOverlay: Identifiable, Equatable, Sendable {
    enum Color: String, CaseIterable, Identifiable, Sendable {
        case white
        case black
        case yellow
        case red
        case blue
        case green

        var id: String { rawValue }

        // Composantes sRGB (0 à 1).
        var rgb: (red: Double, green: Double, blue: Double) {
            switch self {
            case .white: (1, 1, 1)
            case .black: (0, 0, 0)
            case .yellow: (1, 0.84, 0.04)
            case .red: (1, 0.23, 0.19)
            case .blue: (0.04, 0.52, 1)
            case .green: (0.2, 0.78, 0.35)
            }
        }

        var title: String {
            switch self {
            case .white: "Blanc"
            case .black: "Noir"
            case .yellow: "Jaune"
            case .red: "Rouge"
            case .blue: "Bleu"
            case .green: "Vert"
            }
        }
    }

    enum Size: String, CaseIterable, Identifiable, Sendable {
        case small
        case medium
        case large

        var id: String { rawValue }

        // Taille de la police, en part de la largeur de l'image.
        var relativeFontSize: Double {
            switch self {
            case .small: 0.05
            case .medium: 0.075
            case .large: 0.1
            }
        }

        var title: String {
            switch self {
            case .small: "Petit"
            case .medium: "Moyen"
            case .large: "Grand"
            }
        }
    }

    let id: UUID
    var text: String
    var color: Color = .white
    var size: Size = .medium
    // Centre du texte, de 0 à 1 dans chaque dimension (origine en haut à gauche).
    var center = CGPoint(x: 0.5, y: 0.5)
}

// Plan d'édition : fichiers d'origine mis bout à bout, intervalle gardé (dans la durée d'origine), vitesse, filtre, textes.
// Réouvrir l'éditeur repart de ce plan et des fichiers d'origine : jamais de double réencodage.
struct EditPlan: Equatable, Sendable {
    static let minDuration: Duration = .seconds(1)
    static let maxTexts = 5
    static let maxTextLength = 80

    let clips: [SourceClip]
    let kind: PublicationKind
    private(set) var trimStart: Duration = .zero
    private(set) var trimEnd: Duration
    var speed: PlaybackSpeed = .normal
    var filter: VideoFilter = .none
    private(set) var texts: [TextOverlay] = []

    // Intervalle de départ : le début, à la durée maximale (une vidéo de la galerie trop longue est à raccourcir).
    init(clips: [SourceClip], kind: PublicationKind) {
        self.clips = clips
        self.kind = kind
        let total = clips.reduce(Duration.zero) { $0 + $1.duration }
        trimEnd = min(total, kind.maxDuration)
    }

    var sourceDuration: Duration {
        clips.reduce(.zero) { $0 + $1.duration }
    }

    var trimmedDuration: Duration {
        trimEnd - trimStart
    }

    // Durée de la vidéo publiée, après découpage et vitesse.
    var outputDuration: Duration {
        trimmedDuration / speed.rawValue
    }

    var isTrimmed: Bool {
        trimStart > .zero || trimEnd < sourceDuration
    }

    // Sans filtre, texte, changement de vitesse ni assemblage, l'export recopie sans réencodage (qualité et HDR gardés).
    var needsReencoding: Bool {
        clips.count > 1 || filter != .none || !texts.isEmpty || speed != .normal
    }

    // Raison pour laquelle la vidéo ne peut pas être exportée ; nil si elle peut l'être.
    var problem: String? {
        if clips.isEmpty { return "Aucune vidéo." }
        if kind.isTooLong(outputDuration) { return kind.tooLongEditMessage }
        if outputDuration < Self.minDuration { return "La vidéo doit durer au moins 1 seconde." }
        return nil
    }

    // Début et fin bornés : dans la vidéo d'origine, au moins 1 s gardée (`minDuration`, avant la vitesse).
    mutating func setTrimStart(_ start: Duration) {
        trimStart = min(max(.zero, start), max(.zero, trimEnd - Self.minDuration))
    }

    mutating func setTrimEnd(_ end: Duration) {
        trimEnd = max(min(sourceDuration, end), min(sourceDuration, trimStart + Self.minDuration))
    }

    // Texte ajouté (nettoyé) ; nil s'il est vide, trop long, ou s'il y en a déjà 5.
    @discardableResult
    mutating func addText(_ text: String, color: TextOverlay.Color = .white, size: TextOverlay.Size = .medium, id: UUID = UUID())
        -> TextOverlay?
    {
        guard texts.count < Self.maxTexts, let text = Self.sanitizedText(text) else { return nil }
        let overlay = TextOverlay(id: id, text: text, color: color, size: size)
        texts.append(overlay)
        return overlay
    }

    // Texte modifié ; un texte vidé est retiré. Faux si le nouveau texte est trop long.
    @discardableResult
    mutating func updateText(_ id: UUID, text: String, color: TextOverlay.Color, size: TextOverlay.Size) -> Bool {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return false }
        guard let sanitized = Self.sanitizedText(text) else {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.remove(at: index) }
            return false
        }
        texts[index].text = sanitized
        texts[index].color = color
        texts[index].size = size
        return true
    }

    // Déplacé au doigt : le centre reste dans l'image (marge de 5 %).
    mutating func moveText(_ id: UUID, to center: CGPoint) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return }
        texts[index].center = CGPoint(x: min(max(center.x, 0.05), 0.95), y: min(max(center.y, 0.05), 0.95))
    }

    mutating func removeText(_ id: UUID) {
        texts.removeAll { $0.id == id }
    }

    // Texte nettoyé (espaces de bord retirés) ; nil s'il est vide ou dépasse 80 caractères.
    static func sanitizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxTextLength else { return nil }
        return trimmed
    }

    // Fichier d'origine et instant correspondant à `time` dans la durée d'origine (miniatures de la frise).
    func clipPosition(at time: Duration) -> (clip: SourceClip, time: Duration)? {
        var start = Duration.zero
        for clip in clips {
            if time < start + clip.duration || clip == clips.last {
                return (clip, min(max(.zero, time - start), clip.duration))
            }
            start += clip.duration
        }
        return nil
    }
}

// Résumé d'une publication pour la mesure d'audience (ADR-013) : source et modifications, jamais le texte saisi.
struct PublicationDetails: Equatable, Sendable {
    var source: MediaSource = .gallery
    var segments = 1
    var trimmed = false
    var filter: VideoFilter = .none
    var textCount = 0
    var speed: PlaybackSpeed = .normal

    init(source: MediaSource = .gallery, plan: EditPlan? = nil) {
        self.source = source
        guard let plan else { return }
        segments = plan.clips.count
        trimmed = plan.isTrimmed
        filter = plan.filter
        textCount = plan.texts.count
        speed = plan.speed
    }
}
