// Port du lecteur vidéo (ADR-002) : le ViewModel orchestre la lecture sans connaître AVFoundation.
// L'implémentation (data/playback) tient un petit pool de lecteurs, un par vidéo gardée chargée.
@MainActor
protocol VideoPlayback: AnyObject {
    // Garde prêts les lecteurs de ces vidéos (préchargement), et libère tous les autres.
    func keepLoaded(_ videos: [FeedVideo])
    // Lit `videoID` en boucle et met les autres en pause. Une vidéo qui (re)devient courante repart du début ;
    // la vidéo déjà courante reprend là où elle s'était arrêtée.
    func play(_ videoID: String)
    func pauseAll()
    // Position de lecture et durée d'une vidéo chargée (mesure du visionnage, ADR-013) ; nil si elle ne l'est pas.
    func progress(of videoID: String) -> PlaybackProgress?
}

struct PlaybackProgress: Equatable, Sendable {
    // Position dans la boucle en cours.
    let position: Duration
    // Nil tant que le lecteur ne la connaît pas.
    let duration: Duration?
}

extension PlaybackProgress {
    // Part lue de la boucle en cours, entre 0 et 1 (barre de progression du lecteur) ; nil tant que la durée est inconnue.
    var fraction: Double? {
        guard let duration, duration > .zero else { return nil }
        return min(1, max(0, position / duration))
    }
}
