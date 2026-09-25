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
}
