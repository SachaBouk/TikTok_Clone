import Foundation

// Voix off, effets de voix et sons repris (ADR-064) : règles pures, mêlées au son des clips à l'export.

// Voix off enregistrée sur la vidéo : à partir de `start` (temps de la vidéo finale), pendant `duration`, lue dans son
// fichier à partir de `offset` (début enregistré avant que la vidéo ne reparte, sauté).
struct VoiceoverClip: Identifiable, Equatable, Sendable {
    let id: UUID
    let file: URL
    let start: Duration
    var duration: Duration
    var offset: Duration = .zero

    var end: Duration { start + duration }

    func contains(_ time: Duration) -> Bool { time >= start && time < end }
}

// Voix off d'une vidéo de durée `duration` : enregistrées l'une après l'autre, sans chevauchement, chacune de 0,3 s au
// moins. ⌫ retire la dernière enregistrée.
struct VoiceoverTrack: Equatable, Sendable {
    static let minDuration: Duration = .milliseconds(300)

    // Dans l'ordre d'enregistrement.
    private(set) var clips: [VoiceoverClip]
    let duration: Duration

    init(clips: [VoiceoverClip], duration: Duration) {
        self.duration = duration
        self.clips = clips.compactMap { clip in
            guard clip.start < duration else { return nil }
            var clip = clip
            clip.duration = min(clip.duration, duration - clip.start)
            return clip.duration >= Self.minDuration ? clip : nil
        }
    }

    // Dans l'ordre du temps.
    var sorted: [VoiceoverClip] { clips.sorted { $0.start < $1.start } }

    // Durée enregistrable à partir de `time` : jusqu'à la fin de la vidéo ou au début de la voix suivante ; nil si la
    // tête de lecture est sur une voix ou trop près de la fin.
    func available(at time: Duration) -> Duration? {
        guard time >= .zero, !clips.contains(where: { $0.contains(time) }) else { return nil }
        let next = clips.map(\.start).filter { $0 > time }.min() ?? duration
        let available = min(next, duration) - time
        return available >= Self.minDuration ? available : nil
    }

    // Voix ajoutée, raccourcie à la place disponible ; faux si elle est trop courte ou sans place.
    @discardableResult
    mutating func add(_ clip: VoiceoverClip) -> Bool {
        guard let available = available(at: clip.start) else { return false }
        var clip = clip
        clip.duration = min(clip.duration, available)
        guard clip.duration >= Self.minDuration else { return false }
        clips.append(clip)
        return true
    }

    @discardableResult
    mutating func removeLast() -> VoiceoverClip? {
        clips.popLast()
    }
}

// Effets de voix (ADR-064), appliqués à la voix off seulement, par AVAudioEngine dans la couche de données.
enum VoiceEffect: String, CaseIterable, Identifiable, Equatable, Sendable {
    case none
    // Tendances
    case magnetic
    case cave
    case church
    case telephone
    case teenager
    case phonograph
    // Personnages
    case chipmunk
    case giant
    case robot
    case alien
    // Améliorations
    case clear
    case warm
    case radio
    case echo

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case trending
        case characters
        case enhancers

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trending: "Tendances"
            case .characters: "Personnages"
            case .enhancers: "Améliorations"
            }
        }

        var effects: [VoiceEffect] { VoiceEffect.allCases.filter { $0.category == self } }
    }

    var id: String { rawValue }

    var category: Category? {
        switch self {
        case .none: nil
        case .magnetic, .cave, .church, .telephone, .teenager, .phonograph: .trending
        case .chipmunk, .giant, .robot, .alien: .characters
        case .clear, .warm, .radio, .echo: .enhancers
        }
    }

    var title: String {
        switch self {
        case .none: "Aucun"
        case .magnetic: "Magnétique"
        case .cave: "Grotte"
        case .church: "Église"
        case .telephone: "Téléphone"
        case .teenager: "Ado"
        case .phonograph: "Phonographe"
        case .chipmunk: "Écureuil"
        case .giant: "Géant"
        case .robot: "Robot"
        case .alien: "Extraterrestre"
        case .clear: "Voix claire"
        case .warm: "Voix chaude"
        case .radio: "Radio"
        case .echo: "Écho"
        }
    }

    // Symbole SF de sa vignette.
    var symbol: String {
        switch self {
        case .none: "nosign"
        case .magnetic: "bolt.fill"
        case .cave: "mountain.2.fill"
        case .church: "building.columns.fill"
        case .telephone: "phone.fill"
        case .teenager: "face.smiling"
        case .phonograph: "opticaldisc.fill"
        case .chipmunk: "hare.fill"
        case .giant: "figure.stand"
        case .robot: "cpu.fill"
        case .alien: "sparkles"
        case .clear: "waveform"
        case .warm: "flame.fill"
        case .radio: "radio.fill"
        case .echo: "dot.radiowaves.left.and.right"
        }
    }

    // Couleurs du dégradé de sa vignette (sRGB).
    var colors: [(red: Double, green: Double, blue: Double)] {
        switch category {
        case .trending: [(0.78, 0.45, 0.98), (0.35, 0.4, 0.95)]
        case .characters: [(0.98, 0.45, 0.7), (0.55, 0.35, 0.95)]
        case .enhancers: [(0.3, 0.75, 0.95), (0.35, 0.45, 0.9)]
        case nil: [(0.3, 0.3, 0.3), (0.2, 0.2, 0.2)]
        }
    }
}

// Son repris d'une vidéo publiée (ADR-064), tel que proposé par l'API.
struct Sound: Identifiable, Equatable, Sendable {
    let id: String
    let videoID: String
    let author: UserSummary
    let audioURL: URL
    let duration: Duration
    let coverURL: URL
    let usesCount: Int
    var favorited: Bool

    // « Son original - @pseudo ».
    var title: String { "Son original - \(author.username)" }
}

struct SoundPage: Equatable, Sendable {
    let items: [Sound]
    let nextCursor: String?
}

// Son choisi pour la vidéo : téléchargé dans `file`, joué à partir de `start` (✂︎).
struct ChosenSound: Equatable, Sendable {
    let sound: Sound
    let file: URL
    var start: Duration = .zero

    var id: String { sound.id }

    // Début le plus tardif qui garde du son jusqu'à la fin de la vidéo (0 si le son est plus court).
    static func maxStart(soundDuration: Duration, videoDuration: Duration) -> Duration {
        max(.zero, soundDuration - videoDuration)
    }

    // Passage choisi, ramené dans le son.
    func clampedStart(_ start: Duration, videoDuration: Duration) -> Duration {
        min(max(start, .zero), Self.maxStart(soundDuration: sound.duration, videoDuration: videoDuration))
    }
}

// Sons « Récents » de l'éditeur, gardés sur l'iPhone : 30 au plus, le plus récent d'abord, sans doublon.
struct RecentSounds: Equatable, Sendable {
    static let limit = 30

    private(set) var ids: [String]

    init(ids: [String] = []) {
        var seen = Set<String>()
        self.ids = Array(ids.filter { seen.insert($0).inserted }.prefix(Self.limit))
    }

    mutating func use(_ id: String) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.limit { ids.removeLast(ids.count - Self.limit) }
    }
}

// Brouillons (ADR-065).
extension VoiceoverClip: Codable {}
extension VoiceEffect: Codable {}
extension Sound: Codable {}
extension ChosenSound: Codable {}
