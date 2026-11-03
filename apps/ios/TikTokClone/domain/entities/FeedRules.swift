// Règles du lecteur (ADR-002 : « dois-je précharger la vidéo suivante ? » se teste sans AVFoundation).

enum PreloadPolicy {
    // Charger la page suivante quand il reste au plus ce nombre de vidéos après la courante.
    static let loadMoreThreshold = 3

    // Vidéos à garder chargées autour de `index` : la courante d'abord, puis la suivante (le geste le plus
    // fréquent), puis la précédente. Les autres lecteurs sont libérés.
    static func window(around index: Int, count: Int) -> [Int] {
        [index, index + 1, index - 1].filter { (0..<count).contains($0) }
    }

    static func shouldLoadMore(currentIndex: Int, count: Int) -> Bool {
        count - 1 - currentIndex <= loadMoreThreshold
    }
}

// Vues (historique de visionnage, views_count) : une vidéo est comptée après 1 s de lecture, une seule
// fois par session du feed. L'API ne compte de toute façon qu'une vue par compte (views_count).
struct ViewTracker: Sendable {
    static let minimumWatchTime: Duration = .seconds(1)

    private(set) var recorded: Set<String> = []

    func needsRecording(_ videoID: String) -> Bool {
        !recorded.contains(videoID)
    }

    mutating func markRecorded(_ videoID: String) {
        recorded.insert(videoID)
    }
}

// Pastille de republication en bas à gauche d'une page, au-dessus du pseudo (comme TikTok) : « Republier », puis
// « Tu as republié » une fois fait. Rien sur sa propre vidéo. Invité : « Republier » (la connexion s'ouvre).
enum RepostBadge: Equatable {
    case repost
    case reposted

    static func of(_ video: FeedVideo, isOwn: Bool) -> RepostBadge? {
        guard !isOwn else { return nil }
        return video.viewer?.reposted == true ? .reposted : .repost
    }
}

// Cadrage d'une vidéo dans le lecteur plein écran, comme TikTok : une vidéo verticale (9:16 à 2:3) remplit l'écran,
// légèrement recadrée ; une vidéo carrée, en 3:4 ou horizontale est montrée entière, centrée sur fond noir, au lieu
// d'être « zoomée ». Taille inconnue (pas encore chargée) : remplit, comme avant.
enum VideoFraming {
    // Largeur / hauteur au-delà de laquelle la vidéo est ajustée : entre le 2:3 (0,667) et le 3:4 (0,75).
    static let maxFillAspectRatio = 0.7

    static func fills(width: Double, height: Double) -> Bool {
        guard width > 0, height > 0 else { return true }
        return width / height <= maxFillAspectRatio
    }
}

// Plein écran d'une vidéo horizontale, comme TikTok : bouton « Plein écran » sous la vidéo, ou iPhone tourné sur elle ;
// le lecteur passe alors en paysage, et remettre l'iPhone droit le referme.
extension VideoFraming {
    // Largeur / hauteur à partir de laquelle le plein écran est proposé : 4:3 (1,33) et 16:9 (1,78), pas un carré.
    static let minFullScreenAspectRatio = 1.2

    static func offersFullScreen(width: Double, height: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        return width / height >= minFullScreenAspectRatio
    }
}

// Position de l'iPhone, d'après son capteur (indépendante de l'orientation de l'interface).
enum DeviceTilt: Equatable {
    case portrait
    case landscape
    // À plat, à l'envers, inconnue : ne change rien.
    case other
}

enum LandscapeRotation {
    // iPhone tourné sur la vidéo affichée, si elle se regarde en plein écran.
    static func entersFullScreen(tilt: DeviceTilt, offersFullScreen: Bool, isCurrent: Bool) -> Bool {
        tilt == .landscape && offersFullScreen && isCurrent
    }

    // iPhone remis droit pendant le plein écran.
    static func leavesFullScreen(tilt: DeviceTilt) -> Bool {
        tilt == .portrait
    }
}
