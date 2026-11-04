import AVFoundation

// Mesure de la qualité de lecture (ADR-074, Mux Data) : chaque lecteur est suivi de sa création à sa libération. Hors du
// domaine : elle observe des `AVPlayer`, comme le pool qui les crée.
@MainActor
protocol PlaybackMonitor: AnyObject {
    func start(_ player: AVPlayer, video: MonitoredVideo)
    func stop(_ player: AVPlayer)
}

// Vidéo lue : identifiant et provenance (Mux ou le stockage de l'app), sans autre donnée.
struct MonitoredVideo: Equatable, Sendable {
    let id: String
    let cdn: String

    init(id: String, url: URL) {
        self.id = id
        cdn = url.host()?.hasSuffix("mux.com") == true ? "mux" : "minio"
    }
}
