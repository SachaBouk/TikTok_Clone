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

// Texte posé sur la vidéo, visible pendant toute sa durée, comme TikTok : police, couleur, fond, alignement, taille
// (pincer). Position du centre et taille relatives à l'image : le rendu est le même en aperçu et à l'export, quelle que
// soit la résolution.
struct TextOverlay: Identifiable, Equatable, Sendable {
    // Palette de l'éditeur de texte, dans l'ordre de TikTok.
    enum Color: String, CaseIterable, Identifiable, Sendable {
        case white
        case black
        case red
        case orange
        case yellow
        case green
        case teal
        case cyan
        case blue
        case darkBlue
        case indigo
        case purple
        case magenta
        case steel
        case navy
        case sky
        case periwinkle
        case lavender
        case pink
        case salmon
        case cream
        case gray
        case darkGray

        var id: String { rawValue }

        // Composantes sRGB (0 à 1).
        var rgb: (red: Double, green: Double, blue: Double) {
            switch self {
            case .white: (1, 1, 1)
            case .black: (0, 0, 0)
            case .red: (0.91, 0.25, 0.25)
            case .orange: (0.98, 0.56, 0.2)
            case .yellow: (0.95, 0.8, 0.24)
            case .green: (0.44, 0.76, 0.33)
            case .teal: (0.04, 0.69, 0.6)
            case .cyan: (0.04, 0.67, 0.84)
            case .blue: (0.25, 0.6, 0.95)
            case .darkBlue: (0.13, 0.29, 0.7)
            case .indigo: (0.36, 0.36, 0.84)
            case .purple: (0.62, 0.42, 0.95)
            case .magenta: (0.78, 0.2, 0.93)
            case .steel: (0.2, 0.42, 0.6)
            case .navy: (0.13, 0.2, 0.36)
            case .sky: (0.5, 0.85, 0.9)
            case .periwinkle: (0.53, 0.65, 0.97)
            case .lavender: (0.7, 0.66, 0.97)
            case .pink: (0.98, 0.72, 0.96)
            case .salmon: (0.98, 0.65, 0.58)
            case .cream: (0.98, 0.95, 0.6)
            case .gray: (0.56, 0.57, 0.6)
            case .darkGray: (0.2, 0.2, 0.22)
            }
        }

        // Couleur claire (blanc, jaune, roses et bleu ciel pâles…) : un texte posé dessus est écrit en noir ; sur le vert ou
        // le gris, en blanc, comme TikTok.
        var isLight: Bool {
            let (red, green, blue) = rgb
            return 0.299 * red + 0.587 * green + 0.114 * blue > 0.72
        }

        var title: String {
            switch self {
            case .white: "Blanc"
            case .black: "Noir"
            case .red: "Rouge"
            case .orange: "Orange"
            case .yellow: "Jaune"
            case .green: "Vert"
            case .teal: "Turquoise"
            case .cyan: "Cyan"
            case .blue: "Bleu"
            case .darkBlue: "Bleu foncé"
            case .indigo: "Indigo"
            case .purple: "Violet"
            case .magenta: "Magenta"
            case .steel: "Bleu acier"
            case .navy: "Bleu marine"
            case .sky: "Bleu ciel"
            case .periwinkle: "Pervenche"
            case .lavender: "Lavande"
            case .pink: "Rose"
            case .salmon: "Saumon"
            case .cream: "Crème"
            case .gray: "Gris"
            case .darkGray: "Gris foncé"
            }
        }
    }

    // Polices proposées (les fichiers sont choisis par la couche de rendu).
    enum Font: String, CaseIterable, Identifiable, Sendable {
        case classic
        case elegance
        case retro
        case vintage
        case handwriting
        case postcard
        case script
        case technic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .classic: "Classique"
            case .elegance: "Élégance"
            case .retro: "Rétro"
            case .vintage: "Vintage"
            case .handwriting: "Manuscrit"
            case .postcard: "Carte postale"
            case .script: "Script"
            case .technic: "Technique"
            }
        }
    }

    // Fond du texte, changé par le bouton « A » : aucun (texte coloré, ombré), plein (fond de la couleur), transparent.
    enum Background: String, CaseIterable, Identifiable, Sendable {
        case none
        case solid
        case translucent

        var id: String { rawValue }

        var next: Background {
            switch self {
            case .none: .solid
            case .solid: .translucent
            case .translucent: .none
            }
        }

        var title: String {
            switch self {
            case .none: "Sans fond"
            case .solid: "Fond plein"
            case .translucent: "Fond transparent"
            }
        }
    }

    enum Alignment: String, CaseIterable, Identifiable, Sendable {
        case center
        case left
        case right

        var id: String { rawValue }

        var next: Alignment {
            switch self {
            case .center: .left
            case .left: .right
            case .right: .center
            }
        }

        var title: String {
            switch self {
            case .center: "Centré"
            case .left: "Aligné à gauche"
            case .right: "Aligné à droite"
            }
        }
    }

    // Apparence choisie dans l'éditeur de texte.
    struct Style: Equatable, Sendable {
        var color: Color = .white
        var font: Font = .classic
        var background: Background = .none
        var alignment: Alignment = .center

        // Couleur des lettres : la couleur choisie sans fond ; sur un fond, noir ou blanc selon sa clarté.
        var textColor: Color {
            switch background {
            case .none: color
            case .solid: color.isLight ? .black : .white
            case .translucent: color == .white ? .black : .white
            }
        }

        // Fond (couleur et opacité) ; nil sans fond.
        var fill: (color: Color, opacity: Double)? {
            switch background {
            case .none: nil
            case .solid: (color, 1)
            case .translucent: (color, 0.55)
            }
        }
    }

    // Taille de la police à l'échelle 1, en part de la largeur de l'image ; l'échelle se change en pinçant le texte.
    static let baseRelativeFontSize = 0.075
    static let scaleRange: ClosedRange<Double> = 0.4...3

    let id: UUID
    var text: String
    var style = Style()
    var scale: Double = 1
    // Centre du texte, de 0 à 1 dans chaque dimension (origine en haut à gauche).
    var center = CGPoint(x: 0.5, y: 0.5)

    var relativeFontSize: Double { Self.baseRelativeFontSize * scale }
    var color: Color { style.color }
}

// Déplacement d'un texte au doigt, comme TikTok : repère vertical au centre (le texte s'y aimante), corbeille
// « Supprimer » en haut de l'image. Coordonnées relatives à l'image (0 à 1, origine en haut à gauche).
enum TextDragRules {
    // Écart au centre sous lequel le texte s'aimante au repère.
    static let snapDistance = 0.02
    // Corbeille : en haut, au milieu.
    static let trashZone = CGRect(x: 0.3, y: 0, width: 0.4, height: 0.14)

    // Centre aimanté au repère vertical, et vrai si le repère s'affiche.
    static func snapped(_ center: CGPoint) -> (center: CGPoint, onGuide: Bool) {
        guard abs(center.x - 0.5) < snapDistance else { return (center, false) }
        return (CGPoint(x: 0.5, y: center.y), true)
    }

    // Le doigt est sur la corbeille : le texte lâché là est supprimé.
    static func isOverTrash(_ finger: CGPoint) -> Bool {
        trashZone.contains(finger)
    }
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

// Plan d'édition (ADR-052, ADR-062, ADR-063) : clips mis bout à bout, filtre, textes et autocollants communs à toute la
// vidéo, effets sur des plages, son d'origine coupé pour tous. Réouvrir l'éditeur repart de ce plan et des fichiers d'origine : jamais de double réencodage.
struct EditPlan: Equatable, Sendable {
    static let minDuration: Duration = .seconds(1)
    static let maxTexts = 5
    static let maxTextLength = 80
    static let maxStickers = 10

    let kind: PublicationKind
    private(set) var clips: [EditClip]
    var filter: VideoFilter = .none
    // Intensité du filtre, de 0 à 1 (ADR-063).
    private(set) var filterIntensity: Double = 1
    // Son d'origine coupé pour tous les clips (icône haut-parleur de la frise).
    var isMuted = false
    private(set) var texts: [TextOverlay] = []
    private(set) var stickers: [StickerOverlay] = []
    // Effets posés sur des plages de la vidéo finale (ADR-063).
    private(set) var effects: [TimedEffect] = []

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
        clips.count > 1 || clips.contains(where: \.isTransformed) || isMuted || (filter != .none && filterIntensity > 0) || !texts.isEmpty
            || !stickers.isEmpty || !effects.isEmpty
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
    mutating func addText(_ text: String, style: TextOverlay.Style = TextOverlay.Style(), id: UUID = UUID()) -> TextOverlay? {
        guard texts.count < Self.maxTexts, let text = Self.sanitizedText(text) else { return nil }
        let overlay = TextOverlay(id: id, text: text, style: style)
        texts.append(overlay)
        return overlay
    }

    // Texte modifié ; un texte vidé est retiré. Faux si le nouveau texte est trop long.
    @discardableResult
    mutating func updateText(_ id: UUID, text: String, style: TextOverlay.Style) -> Bool {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return false }
        guard let sanitized = Self.sanitizedText(text) else {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.remove(at: index) }
            return false
        }
        texts[index].text = sanitized
        texts[index].style = style
        return true
    }

    // Pincé : l'échelle reste dans `TextOverlay.scaleRange`.
    mutating func scaleText(_ id: UUID, to scale: Double) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return }
        texts[index].scale = min(max(scale, TextOverlay.scaleRange.lowerBound), TextOverlay.scaleRange.upperBound)
    }

    // Déplacé au doigt : le centre reste dans l'image (marge de 5 %).
    mutating func moveText(_ id: UUID, to center: CGPoint) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return }
        texts[index].center = CGPoint(x: min(max(center.x, 0.05), 0.95), y: min(max(center.y, 0.05), 0.95))
    }

    mutating func removeText(_ id: UUID) {
        texts.removeAll { $0.id == id }
    }

    mutating func setFilterIntensity(_ intensity: Double) {
        filterIntensity = min(max(intensity, 0), 1)
    }

    // Autocollant ajouté au centre ; nil s'il y en a déjà 10 ou si son texte est vide.
    @discardableResult
    mutating func addSticker(_ kind: StickerOverlay.Kind, text: String, id: UUID = UUID()) -> StickerOverlay? {
        guard stickers.count < Self.maxStickers, !text.isEmpty else { return nil }
        let sticker = StickerOverlay(id: id, kind: kind, text: text)
        stickers.append(sticker)
        return sticker
    }

    // Déplacé au doigt : le centre reste dans l'image (marge de 5 %).
    mutating func moveSticker(_ id: UUID, to center: CGPoint) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[index].center = CGPoint(x: min(max(center.x, 0.05), 0.95), y: min(max(center.y, 0.05), 0.95))
    }

    mutating func scaleSticker(_ id: UUID, to scale: Double) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[index].scale = min(max(scale, StickerOverlay.scaleRange.lowerBound), StickerOverlay.scaleRange.upperBound)
    }

    mutating func removeSticker(_ id: UUID) {
        stickers.removeAll { $0.id == id }
    }

    // Plages d'effets de l'éditeur d'effets, ramenées à la durée de la vidéo.
    mutating func setEffects(_ effects: [TimedEffect]) {
        self.effects = EffectTrack(effects: effects, duration: outputDuration).effects
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
    // Intensité du filtre, de 0 à 100 (ADR-063).
    var filterIntensity = 100
    var textCount = 0
    var stickerCount = 0
    var effectCount = 0
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
        filterIntensity = Int((plan.filterIntensity * 100).rounded())
        textCount = plan.texts.count
        stickerCount = plan.stickers.count
        effectCount = plan.effects.count
        speed = plan.commonSpeed ?? 0
        cropped = plan.clips.contains { !$0.crop.isFull }
        rotated = plan.clips.contains { $0.quarterTurns != 0 }
    }
}
