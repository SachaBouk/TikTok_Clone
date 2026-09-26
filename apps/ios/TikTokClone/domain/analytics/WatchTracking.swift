import Foundation

// Règles de la mesure du visionnage (ADR-013), testées sans AVFoundation (ADR-002).

// Une vidéo regardée, de son affichage au passage à une autre (ou à la sortie de l'écran).
struct VideoWatch: Equatable, Sendable {
    // Au moins cette part de la vidéo pour la considérer comme vue en entier.
    static let completedRatio = 0.9

    let videoID: String
    let authorID: String
    let source: VideoSource
    // Temps de lecture effectif (pauses exclues), boucles comprises.
    let watched: Duration
    // Durée de la vidéo, si le lecteur la connaît déjà.
    let duration: Duration?
    // Position dans la vidéo au moment de la quitter (moment du swipe).
    let exitPosition: Duration?
    let exit: WatchExit

    // Temps regardé rapporté à la durée : 0,5 = la moitié, 2 = deux lectures complètes.
    var completion: Double? {
        guard let duration, duration > .zero else { return nil }
        return (watched.seconds / duration.seconds * 100).rounded() / 100
    }

    var completed: Bool { (completion ?? 0) >= Self.completedRatio }

    // Lectures complètes (la vidéo tourne en boucle).
    var loops: Int { Int(completion ?? 0) }
}

// Chronomètre du visionnage de la vidéo courante : ne compte que le temps de lecture (pas les pauses).
struct WatchTimer: Sendable {
    private(set) var videoID: String?
    private var accumulated: Duration = .zero
    private var playingSince: Date?

    var isPlaying: Bool { playingSince != nil }

    // Nouvelle vidéo courante, en lecture.
    mutating func start(_ videoID: String, at date: Date) {
        self.videoID = videoID
        accumulated = .zero
        playingSince = date
    }

    mutating func pause(at date: Date) {
        guard let since = playingSince else { return }
        accumulated += .seconds(max(0, date.timeIntervalSince(since)))
        playingSince = nil
    }

    mutating func resume(at date: Date) {
        guard videoID != nil, playingSince == nil else { return }
        playingSince = date
    }

    // Fin du visionnage : la vidéo et son temps de lecture, puis le chronomètre repart de zéro.
    mutating func finish(at date: Date) -> (videoID: String, watched: Duration)? {
        pause(at: date)
        defer {
            videoID = nil
            accumulated = .zero
        }
        guard let videoID, accumulated > .zero else { return nil }
        return (videoID, accumulated)
    }
}

// Expérience A/B « invitation invité » (ADR-013, choix du développeur) : feature flag multivarié. Témoin : rien ;
// variante : la feuille de connexion s'ouvre avec une invitation après quelques vidéos regardées sans compte.
// Le flag est lu une seule fois par installation, au moment où l'invitation serait montrée : les deux groupes sont
// exposés au même moment (événement `$feature_flag_called` de PostHog).
enum GuestPromptExperiment {
    static let flag = "guest-signup-prompt"
    static let promptVariant = "prompt"
    // Vidéos différentes regardées au moins 1 s (comme une vue) avant l'invitation.
    static let videosBeforePrompt = 5
    static let message = "Crée ton compte pour aimer, commenter, suivre des créateurs et publier tes vidéos."
}

// Vidéos regardées en invité, jusqu'au seuil de l'expérience.
struct GuestWatchCounter: Sendable {
    private(set) var watched: Set<String> = []

    // Vrai la première fois que le seuil est atteint.
    mutating func record(_ videoID: String) -> Bool {
        guard watched.count < GuestPromptExperiment.videosBeforePrompt else { return false }
        watched.insert(videoID)
        return watched.count == GuestPromptExperiment.videosBeforePrompt
    }
}
