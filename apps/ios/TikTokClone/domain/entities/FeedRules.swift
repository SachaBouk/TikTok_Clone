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
