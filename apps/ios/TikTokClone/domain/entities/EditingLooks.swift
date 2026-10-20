import CoreGraphics
import Foundation

// Filtres, autocollants et effets de l'éditeur (ADR-063) : règles pures, rendues à l'export par la couche de données.

// Filtres de couleur (Core Image, dans l'adaptateur d'export), rangés par catégorie comme TikTok ; l'identifiant sert
// aussi à la mesure d'audience (ceux d'avant l'ADR-063 sont gardés, dans « Ambiance »).
enum VideoFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case none
    // Portrait
    case natural
    case sunny
    case vitality
    case warmth
    case soft
    // Paysage
    case holiday
    case forest
    case chill
    case dusk
    case california
    // Nourriture
    case tasty
    case crisp
    case fresh
    case golden
    // Ambiance
    case mono
    case warm
    case cool
    case vivid
    case vintage
    case fade
    case instant
    case noir
    case chrome

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case portrait
        case landscape
        case food
        case mood

        var id: String { rawValue }

        var title: String {
            switch self {
            case .portrait: "Portrait"
            case .landscape: "Paysage"
            case .food: "Nourriture"
            case .mood: "Ambiance"
            }
        }

        var filters: [VideoFilter] { VideoFilter.allCases.filter { $0.category == self } }
    }

    var id: String { rawValue }

    // nil pour « aucun filtre ».
    var category: Category? {
        switch self {
        case .none: nil
        case .natural, .sunny, .vitality, .warmth, .soft: .portrait
        case .holiday, .forest, .chill, .dusk, .california: .landscape
        case .tasty, .crisp, .fresh, .golden: .food
        case .mono, .warm, .cool, .vivid, .vintage, .fade, .instant, .noir, .chrome: .mood
        }
    }

    var title: String {
        switch self {
        case .none: "Aucun"
        case .natural: "Naturel"
        case .sunny: "Soleil"
        case .vitality: "Vitalité"
        case .warmth: "Chaleur"
        case .soft: "Doux"
        case .holiday: "Vacances"
        case .forest: "Forêt"
        case .chill: "Détente"
        case .dusk: "Crépuscule"
        case .california: "Californie"
        case .tasty: "Gourmand"
        case .crisp: "Croquant"
        case .fresh: "Frais"
        case .golden: "Doré"
        case .mono: "Noir et blanc"
        case .warm: "Chaud"
        case .cool: "Froid"
        case .vivid: "Vif"
        case .vintage: "Vintage"
        case .fade: "Fondu"
        case .instant: "Instantané"
        case .noir: "Film noir"
        case .chrome: "Chrome"
        }
    }
}

// Autocollant posé sur la vidéo (ADR-063) : emoji, date ou heure (figées au moment de l'ajout), visible pendant toute la
// vidéo. Position du centre et taille relatives à l'image, comme les textes.
struct StickerOverlay: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case emoji
        // « 20/10 »
        case dateSlash
        // « 20-10-26 »
        case dateDash
        // « 16:42 »
        case time

        // Taille de la police à l'échelle 1, en part de la largeur de l'image.
        var baseRelativeSize: Double {
            switch self {
            case .emoji: 0.2
            case .dateSlash, .dateDash, .time: 0.16
            }
        }

        var title: String {
            switch self {
            case .emoji: "Emoji"
            case .dateSlash, .dateDash: "Date"
            case .time: "Heure"
            }
        }
    }

    static let scaleRange: ClosedRange<Double> = 0.3...4

    let id: UUID
    let kind: Kind
    let text: String
    var scale: Double = 1
    var center = CGPoint(x: 0.5, y: 0.5)

    var relativeFontSize: Double { kind.baseRelativeSize * scale }

    // Texte d'un autocollant de date ou d'heure à l'instant `date` (calendrier de l'appareil).
    static func text(for kind: Kind, at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month, .year, .hour, .minute], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        switch kind {
        case .emoji: return ""
        case .dateSlash: return "\(two(parts.day))/\(two(parts.month))"
        case .dateDash: return "\(two(parts.day))-\(two(parts.month))-\(two((parts.year ?? 0) % 100))"
        case .time: return "\(two(parts.hour)):\(two(parts.minute))"
        }
    }
}

// Emojis proposés, par catégorie (barre du bas du panneau « Emoji »).
enum EmojiCatalog {
    struct Section: Identifiable, Sendable {
        let id: String
        let title: String
        let icon: String
        let emojis: [String]
    }

    static let sections: [Section] = [
        Section(
            id: "smileys", title: "Émotions", icon: "😀",
            emojis: [
                "😀", "😂", "🤣", "😊", "😍", "🥰", "😘", "😎", "🤩", "🥳", "😇", "🙃", "😉", "😋", "😜", "🤪", "🤔", "🤫", "😴", "😱",
                "😭", "😡", "🥺", "😳", "🤯", "😬", "🙄", "😏", "🤗", "🫶",
            ]),
        Section(
            id: "hearts", title: "Cœurs et gestes", icon: "❤️",
            emojis: [
                "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💖", "💕", "💔", "💯", "👍", "👎", "👏", "🙌", "🙏", "💪", "✌️", "🤞",
                "👌", "🤙", "👋", "🫡",
            ]),
        Section(
            id: "nature", title: "Animaux et nature", icon: "🐶",
            emojis: [
                "🐶", "🐱", "🦊", "🐻", "🐼", "🐨", "🦁", "🐸", "🐵", "🦄", "🐝", "🦋", "🌸", "🌻", "🌹", "🌴", "🌵", "🍀", "🌈", "☀️",
                "🌙", "⭐️", "❄️", "🌊",
            ]),
        Section(
            id: "food", title: "Nourriture", icon: "🍕",
            emojis: [
                "🍕", "🍔", "🍟", "🌭", "🌮", "🍣", "🍜", "🍩", "🍪", "🎂", "🍰", "🍫", "🍿", "🍓", "🍉", "🍑", "🥑", "🍋", "☕️", "🧋",
                "🍹", "🥂", "🍾", "🍦",
            ]),
        Section(
            id: "activities", title: "Activités", icon: "⚽️",
            emojis: [
                "⚽️", "🏀", "🎾", "🏐", "🏈", "🎮", "🎧", "🎤", "🎸", "🎹", "🎨", "🎬", "📸", "🎉", "🎊", "🎁", "🏆", "🥇", "✈️", "🚗",
                "🏖️", "🏔️", "🎢", "🛹",
            ]),
        Section(
            id: "symbols", title: "Symboles", icon: "✨",
            emojis: [
                "✨", "🔥", "💥", "💫", "⚡️", "💎", "🎵", "🎶", "💬", "💭", "❗️", "❓", "✅", "❌", "⭕️", "💤", "👀", "👑", "💋", "🌟",
                "📍", "⏰", "💡", "🔮",
            ]),
    ]
}

// Effets visuels (ADR-063, version réduite) : posés sur une plage de la vidéo finale, rendus par Core Image après le
// filtre.
enum VideoEffect: String, CaseIterable, Identifiable, Equatable, Sendable {
    case overExposure
    case blackNoise
    case blur
    case glow
    case vignette
    case negative
    case retroBlue
    case posterize
    case comic
    case pixelate
    case mirror
    case twirl
    case bump

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case visual
        case color
        case distortion

        var id: String { rawValue }

        var title: String {
            switch self {
            case .visual: "Visuel"
            case .color: "Couleur"
            case .distortion: "Déformation"
            }
        }

        var effects: [VideoEffect] { VideoEffect.allCases.filter { $0.category == self } }
    }

    var id: String { rawValue }

    var category: Category {
        switch self {
        case .overExposure, .blackNoise, .blur, .glow, .vignette: .visual
        case .negative, .retroBlue, .posterize, .comic: .color
        case .pixelate, .mirror, .twirl, .bump: .distortion
        }
    }

    var title: String {
        switch self {
        case .overExposure: "Surexposition"
        case .blackNoise: "Bruit noir"
        case .blur: "Flou"
        case .glow: "Lueur"
        case .vignette: "Vignette"
        case .negative: "Négatif"
        case .retroBlue: "Rétro bleu"
        case .posterize: "Affiche"
        case .comic: "Bande dessinée"
        case .pixelate: "Pixels"
        case .mirror: "Miroir"
        case .twirl: "Tourbillon"
        case .bump: "Loupe"
        }
    }

    // Couleur de sa plage dans la frise (sRGB).
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .overExposure: (0.98, 0.42, 0.2)
        case .blackNoise: (0.45, 0.45, 0.5)
        case .blur: (0.35, 0.65, 0.98)
        case .glow: (0.98, 0.78, 0.25)
        case .vignette: (0.6, 0.4, 0.25)
        case .negative: (0.72, 0.3, 0.86)
        case .retroBlue: (0.2, 0.45, 0.9)
        case .posterize: (0.95, 0.3, 0.55)
        case .comic: (0.95, 0.85, 0.2)
        case .pixelate: (0.25, 0.78, 0.55)
        case .mirror: (0.3, 0.8, 0.85)
        case .twirl: (0.55, 0.35, 0.95)
        case .bump: (0.9, 0.5, 0.3)
        }
    }
}

// Effet posé sur la plage [start, end[ de la vidéo finale.
struct TimedEffect: Identifiable, Equatable, Sendable {
    let id: UUID
    let effect: VideoEffect
    var start: Duration
    var end: Duration

    var duration: Duration { end - start }

    func contains(_ time: Duration) -> Bool { time >= start && time < end }
}

// Plages d'effets de l'éditeur d'effets : ajout à la tête de lecture, bords déplacés, suppression ; toujours dans la
// vidéo, 0,2 s au moins, 20 au plus.
struct EffectTrack: Equatable, Sendable {
    static let maxEffects = 20
    static let defaultDuration: Duration = .seconds(2)
    static let minDuration: Duration = .milliseconds(200)

    private(set) var effects: [TimedEffect]
    let duration: Duration

    init(effects: [TimedEffect], duration: Duration) {
        self.duration = duration
        self.effects = effects.compactMap { effect in
            var effect = effect
            effect.end = min(effect.end, duration)
            return effect.duration >= Self.minDuration ? effect : nil
        }
    }

    // Effet posé à partir de `time` pour 2 s (ou jusqu'à la fin) ; nil s'il y en a déjà 20 ou si la fin est trop proche.
    @discardableResult
    mutating func add(_ effect: VideoEffect, at time: Duration, id: UUID = UUID()) -> TimedEffect? {
        guard effects.count < Self.maxEffects, duration >= Self.minDuration else { return nil }
        let start = min(max(time, .zero), duration - Self.minDuration)
        let added = TimedEffect(id: id, effect: effect, start: start, end: min(start + Self.defaultDuration, duration))
        effects.append(added)
        return added
    }

    // Bord gauche : entre 0 et la fin moins 0,2 s.
    mutating func setStart(_ start: Duration, of id: UUID) {
        guard let index = effects.firstIndex(where: { $0.id == id }) else { return }
        effects[index].start = min(max(start, .zero), effects[index].end - Self.minDuration)
    }

    // Bord droit : entre le début plus 0,2 s et la fin de la vidéo.
    mutating func setEnd(_ end: Duration, of id: UUID) {
        guard let index = effects.firstIndex(where: { $0.id == id }) else { return }
        effects[index].end = max(min(end, duration), effects[index].start + Self.minDuration)
    }

    mutating func remove(_ id: UUID) {
        effects.removeAll { $0.id == id }
    }

    // Effets actifs à `time`, dans l'ordre où ils ont été posés.
    static func active(_ effects: [TimedEffect], at time: Duration) -> [VideoEffect] {
        effects.filter { $0.contains(time) }.map(\.effect)
    }
}
