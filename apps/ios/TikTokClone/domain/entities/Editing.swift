import CoreGraphics
import Foundation

// Enregistrement et édition vidéo dans l'app (ADR-052, ADR-062) : segments filmés par la caméra ou vidéos de la galerie,
// puis plan d'édition par clips appliqué à l'export sur l'iPhone. Règles pures, testées sans AVFoundation (ADR-002).

// Origine du média publié (mesure d'audience).
enum MediaSource: String, Equatable, Sendable {
    case camera
    case gallery
    // Story « nouvelle photo de profil », dessinée par l'app (ADR-056).
    case profilePhoto = "profile_photo"
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

    // `limit` : durée choisie sur la caméra (« 60 s », « 15 s », ADR-062), jamais au-delà de celle de la publication.
    init(kind: PublicationKind, limit: Duration? = nil) {
        maxDuration = min(limit ?? kind.maxDuration, kind.maxDuration)
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

// Durées proposées au-dessus du déclencheur de la caméra (ADR-062) : la vidéo filmée s'arrête seule à la limite.
enum RecordingLimit: CaseIterable, Identifiable, Equatable, Sendable {
    case threeMinutes
    case sixtySeconds
    case fifteenSeconds

    var id: Self { self }

    var duration: Duration {
        switch self {
        case .threeMinutes: .seconds(180)
        case .sixtySeconds: .seconds(60)
        case .fifteenSeconds: .seconds(15)
        }
    }

    var title: String {
        switch self {
        case .threeMinutes: "3 min"
        case .sixtySeconds: "60 s"
        case .fifteenSeconds: "15 s"
        }
    }
}

// Vitesse d'un clip, de 0,1× à 10× (ADR-062) : curseur à graduations non linéaires, comme TikTok (0,1×, 1×, 2×, 5×,
// 10× à intervalles égaux), valeur arrondie au dixième. La hauteur du son est gardée.
enum SpeedScale {
    static let range: ClosedRange<Double> = 0.1...10
    // Repères du curseur, à intervalles égaux.
    static let marks: [Double] = [0.1, 1, 2, 5, 10]

    // Vitesse au point `fraction` (0 à 1) du curseur.
    static func speed(at fraction: Double) -> Double {
        let position = min(max(fraction, 0), 1) * Double(marks.count - 1)
        let index = min(Int(position), marks.count - 2)
        let local = position - Double(index)
        let value = marks[index] + (marks[index + 1] - marks[index]) * local
        return clamped((value * 10).rounded() / 10)
    }

    // Position (0 à 1) de `speed` sur le curseur.
    static func fraction(of speed: Double) -> Double {
        let value = clamped(speed)
        for index in 0..<(marks.count - 1) where value <= marks[index + 1] {
            let local = (value - marks[index]) / (marks[index + 1] - marks[index])
            return (Double(index) + local) / Double(marks.count - 1)
        }
        return 1
    }

    static func clamped(_ speed: Double) -> Double {
        min(max(speed, range.lowerBound), range.upperBound)
    }

    // « 1,2x », « 10x », comme les repères du curseur.
    static func label(_ speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR"))))x"
    }
}

// Rectangle gardé d'un clip, relatif à son image tournée (0 à 1, origine en haut à gauche).
struct CropRect: Equatable, Sendable {
    static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isFull: Bool { self == .full }
}

// Proportions proposées par « Recadrer » (ADR-062).
enum CropRatio: String, CaseIterable, Identifiable, Equatable, Sendable {
    case free
    case portrait
    case landscape
    case square
    case classicPortrait
    case classicLandscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Libre"
        case .portrait: "9:16"
        case .landscape: "16:9"
        case .square: "1:1"
        case .classicPortrait: "3:4"
        case .classicLandscape: "4:3"
        }
    }

    // Largeur / hauteur ; nil pour un cadre libre.
    var value: Double? {
        switch self {
        case .free: nil
        case .portrait: 9.0 / 16.0
        case .landscape: 16.0 / 9.0
        case .square: 1
        case .classicPortrait: 3.0 / 4.0
        case .classicLandscape: 4.0 / 3.0
        }
    }
}

// Règles du cadre de recadrage, dans une image de proportions `frameAspect` (largeur / hauteur).
enum CropRules {
    // Côté minimal du cadre, relatif à l'image.
    static let minSize = 0.1

    enum Corner: CaseIterable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    // Plus grand cadre centré aux proportions `ratio` ; l'image entière pour un cadre libre.
    static func initial(ratio: CropRatio, frameAspect: Double) -> CropRect {
        guard let value = ratio.value, frameAspect > 0 else { return .full }
        // Largeur relative / hauteur relative pour ces proportions.
        let relative = value / frameAspect
        let width = relative <= 1 ? relative : 1
        let height = relative <= 1 ? 1 : 1 / relative
        return CropRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    // Cadre déplacé, sans sortir de l'image.
    static func moved(_ rect: CropRect, dx: Double, dy: Double) -> CropRect {
        var moved = rect
        moved.x = min(max(rect.x + dx, 0), 1 - rect.width)
        moved.y = min(max(rect.y + dy, 0), 1 - rect.height)
        return moved
    }

    // Cadre agrandi ou réduit par un coin (le coin opposé reste en place) ; proportions gardées si `ratio` en fixe.
    static func resized(_ rect: CropRect, corner: Corner, dx: Double, dy: Double, ratio: CropRatio, frameAspect: Double) -> CropRect {
        let left = corner == .topLeading || corner == .bottomLeading
        let top = corner == .topLeading || corner == .topTrailing
        // Coin opposé, fixe.
        let anchorX = left ? rect.x + rect.width : rect.x
        let anchorY = top ? rect.y + rect.height : rect.y
        let maxWidth = left ? anchorX : 1 - anchorX
        let maxHeight = top ? anchorY : 1 - anchorY
        var width = min(max(rect.width + (left ? -dx : dx), minSize), maxWidth)
        var height = min(max(rect.height + (top ? -dy : dy), minSize), maxHeight)
        if let value = ratio.value, frameAspect > 0 {
            let relative = value / frameAspect
            // La largeur mène ; la hauteur suit, puis la largeur est ramenée si la hauteur bute.
            height = width / relative
            if height > maxHeight {
                height = maxHeight
                width = height * relative
            }
            if height < minSize {
                height = minSize
                width = min(height * relative, maxWidth)
            }
        }
        return CropRect(x: left ? anchorX - width : anchorX, y: top ? anchorY - height : anchorY, width: width, height: height)
    }
}

// Clip de la frise (ADR-062) : un fichier d'origine, l'intervalle gardé, sa vitesse, son volume, son cadre et sa rotation.
struct EditClip: Identifiable, Equatable, Sendable {
    // Plus court clip possible (découpage, division).
    static let minDuration: Duration = .milliseconds(100)

    let id: UUID
    let source: SourceClip
    fileprivate(set) var start: Duration = .zero
    fileprivate(set) var end: Duration
    fileprivate(set) var speed: Double = 1
    // Volume du son d'origine, de 0 à 1.
    fileprivate(set) var volume: Double = 1
    fileprivate(set) var crop: CropRect = .full
    fileprivate(set) var cropRatio: CropRatio = .free
    // Quarts de tour dans le sens des aiguilles d'une montre (0 à 3).
    fileprivate(set) var quarterTurns = 0

    init(source: SourceClip, id: UUID = UUID()) {
        self.id = id
        self.source = source
        end = source.duration
    }

    var keptDuration: Duration { end - start }
    // Durée dans la vidéo finale, après la vitesse.
    var outputDuration: Duration { keptDuration / speed }
    var isTrimmed: Bool { start > .zero || end < source.duration }
    // Seul le découpage ne demande pas de réencodage.
    var isTransformed: Bool { speed != 1 || volume != 1 || !crop.isFull || quarterTurns != 0 }
}

// Plan d'édition (ADR-052, ADR-062) : clips mis bout à bout, filtre et textes communs à toute la vidéo, son d'origine
// coupé pour tous. Réouvrir l'éditeur repart de ce plan et des fichiers d'origine : jamais de double réencodage.
struct EditPlan: Equatable, Sendable {
    static let minDuration: Duration = .seconds(1)
    static let maxTexts = 5
    static let maxTextLength = 80

    let kind: PublicationKind
    private(set) var clips: [EditClip]
    var filter: VideoFilter = .none
    // Son d'origine coupé pour tous les clips (icône haut-parleur de la frise).
    var isMuted = false
    private(set) var texts: [TextOverlay] = []

    // Une vidéo trop longue est raccourcie à la durée maximale (la fin est retirée) : le passage à garder se choisit
    // ensuite dans la frise. À une seconde près (ADR-040), elle est gardée entière.
    init(clips sources: [SourceClip], kind: PublicationKind) {
        self.kind = kind
        let total = sources.reduce(Duration.zero) { $0 + $1.duration }
        var remaining = kind.isTooLong(total) ? kind.maxDuration : total
        var clips: [EditClip] = []
        for source in sources {
            var clip = EditClip(source: source)
            if remaining < source.duration, remaining >= EditClip.minDuration { clip.end = remaining }
            remaining = max(.zero, remaining - clip.keptDuration)
            clips.append(clip)
        }
        self.clips = clips
    }

    // Fichiers d'origine, sans doublon (un clip divisé garde le même fichier).
    var sources: [SourceClip] {
        var seen = Set<URL>()
        return clips.map(\.source).filter { seen.insert($0.file).inserted }
    }

    // Durée de la vidéo publiée, après découpage et vitesse.
    var outputDuration: Duration {
        clips.reduce(.zero) { $0 + $1.outputDuration }
    }

    var isTrimmed: Bool { clips.contains(where: \.isTrimmed) }

    // Un seul clip seulement découpé : l'export recopie sans réencodage (qualité et HDR gardés).
    var needsReencoding: Bool {
        clips.count > 1 || clips.contains(where: \.isTransformed) || isMuted || filter != .none || !texts.isEmpty
    }

    // Raison pour laquelle la vidéo ne peut pas être exportée ; nil si elle peut l'être.
    var problem: String? {
        if clips.isEmpty { return "Aucune vidéo." }
        if kind.isTooLong(outputDuration) { return kind.tooLongEditMessage }
        if outputDuration < Self.minDuration { return "La vidéo doit durer au moins 1 seconde." }
        return nil
    }

    // Vitesse commune à tous les clips ; nil si elles diffèrent.
    var commonSpeed: Double? {
        let speeds = Set(clips.map(\.speed))
        return speeds.count == 1 ? speeds.first : nil
    }

    func clip(_ id: UUID) -> EditClip? {
        clips.first { $0.id == id }
    }

    // Instant de la vidéo finale où commence le clip `index`.
    func startTime(ofClipAt index: Int) -> Duration {
        clips.prefix(index).reduce(.zero) { $0 + $1.outputDuration }
    }

    // Clip à l'instant `time` de la vidéo finale, et l'instant correspondant dans son fichier d'origine.
    func locate(_ time: Duration) -> (index: Int, sourceTime: Duration)? {
        guard !clips.isEmpty else { return nil }
        var start = Duration.zero
        for (index, clip) in clips.enumerated() {
            let end = start + clip.outputDuration
            if time < end || index == clips.count - 1 {
                let local = min(max(.zero, time - start), clip.outputDuration)
                return (index, min(clip.start + local * clip.speed, clip.end))
            }
            start = end
        }
        return nil
    }

    // Divise le clip sous la tête de lecture (`time`, dans la vidéo finale) ; faux si l'un des deux morceaux serait
    // trop court. Les deux gardent les réglages du clip.
    @discardableResult
    mutating func split(at time: Duration, newID: UUID = UUID()) -> Bool {
        guard let (index, sourceTime) = locate(time) else { return false }
        let clip = clips[index]
        guard sourceTime - clip.start >= EditClip.minDuration, clip.end - sourceTime >= EditClip.minDuration else { return false }
        var first = clip
        first.end = sourceTime
        // Nouvel identifiant : les deux morceaux sont deux clips de la frise.
        var second = EditClip(source: clip.source, id: newID)
        second.start = sourceTime
        second.end = clip.end
        second.speed = clip.speed
        second.volume = clip.volume
        second.crop = clip.crop
        second.cropRatio = clip.cropRatio
        second.quarterTurns = clip.quarterTurns
        clips.replaceSubrange(index...index, with: [first, second])
        return true
    }

    // Faux pour le dernier clip restant.
    @discardableResult
    mutating func removeClip(_ id: UUID) -> Bool {
        guard clips.count > 1, let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        clips.remove(at: index)
        return true
    }

    // Vidéos ajoutées au bout de la frise (« + »).
    mutating func append(_ sources: [SourceClip]) {
        clips.append(contentsOf: sources.map { EditClip(source: $0) })
    }

    // Début et fin d'un clip, dans son fichier d'origine : au moins `EditClip.minDuration` gardé.
    mutating func setStart(_ start: Duration, of id: UUID) {
        update(id) { $0.start = min(max(.zero, start), $0.end - EditClip.minDuration) }
    }

    mutating func setEnd(_ end: Duration, of id: UUID) {
        update(id) { $0.end = max(min($0.source.duration, end), $0.start + EditClip.minDuration) }
    }

    mutating func setSpeed(_ speed: Double, of id: UUID) {
        update(id) { $0.speed = SpeedScale.clamped(speed) }
    }

    // « Appliquer à tout » : vitesse de tous les clips.
    mutating func setSpeedForAll(_ speed: Double) {
        for clip in clips { setSpeed(speed, of: clip.id) }
    }

    mutating func setVolume(_ volume: Double, of id: UUID) {
        update(id) { $0.volume = min(max(volume, 0), 1) }
    }

    mutating func setVolumeForAll(_ volume: Double) {
        for clip in clips { setVolume(volume, of: clip.id) }
    }

    // Quart de tour : le cadre repart de l'image entière (ses proportions ont changé).
    mutating func rotate(_ id: UUID) {
        update(id) {
            $0.quarterTurns = ($0.quarterTurns + 1) % 4
            $0.crop = .full
            $0.cropRatio = .free
        }
    }

    mutating func setCrop(_ crop: CropRect, ratio: CropRatio, of id: UUID) {
        update(id) {
            let width = min(max(crop.width, CropRules.minSize), 1)
            let height = min(max(crop.height, CropRules.minSize), 1)
            $0.crop = CropRect(x: min(max(crop.x, 0), 1 - width), y: min(max(crop.y, 0), 1 - height), width: width, height: height)
            $0.cropRatio = ratio
        }
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

    private mutating func update(_ id: UUID, _ change: (inout EditClip) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        change(&clips[index])
    }
}

// Annuler / rétablir de l'éditeur (ADR-062) : états successifs du plan.
struct EditHistory<State: Equatable & Sendable>: Sendable {
    static var limit: Int { 50 }

    private(set) var undoStack: [State] = []
    private(set) var redoStack: [State] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // `previous` : l'état avant un changement ; rien si rien n'a changé.
    mutating func record(_ previous: State, current: State) {
        guard previous != current else { return }
        undoStack.append(previous)
        if undoStack.count > Self.limit { undoStack.removeFirst() }
        redoStack = []
    }

    mutating func undo(_ current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(_ current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}

// Résumé d'une publication pour la mesure d'audience (ADR-013) : source et modifications, jamais le texte saisi.
struct PublicationDetails: Equatable, Sendable {
    var source: MediaSource = .gallery
    var segments = 1
    var trimmed = false
    var filter: VideoFilter = .none
    var textCount = 0
    // Vitesse commune ; 0 si les clips ont des vitesses différentes.
    var speed: Double = 1
    var cropped = false
    var rotated = false

    init(source: MediaSource = .gallery, plan: EditPlan? = nil) {
        self.source = source
        guard let plan else { return }
        segments = plan.clips.count
        trimmed = plan.isTrimmed
        filter = plan.filter
        textCount = plan.texts.count
        speed = plan.commonSpeed ?? 0
        cropped = plan.clips.contains { !$0.crop.isFull }
        rotated = plan.clips.contains { $0.quarterTurns != 0 }
    }
}
