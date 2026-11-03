import AVFoundation
import Observation

// Pool de lecteurs AVPlayer (ADR-002) : un lecteur par vidéo gardée chargée (la courante et ses voisines,
// voir PreloadPolicy), libéré dès qu'elle sort de la fenêtre. Chaque lecteur boucle (AVPlayerLooper).
// Observable : la vue affiche le lecteur d'une vidéo dès qu'il existe.
@MainActor
@Observable
final class AVPlayerPool: VideoPlayback {
    private struct Entry {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
    }

    // Tampon réduit pour les vidéos préchargées : démarrage rapide sans télécharger toute la vidéo voisine.
    static let forwardBufferDuration: TimeInterval = 4

    private var entries: [String: Entry] = [:]
    private var currentID: String?
    // Vitesse de lecture (`FastPlayback`) : celle de chaque lecteur au démarrage (`defaultRate`).
    private var rate: Float = 1

    init() {
        // Le son joue même en mode silencieux, comme une app vidéo.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    func player(for videoID: String) -> AVPlayer? {
        entries[videoID]?.player
    }

    func keepLoaded(_ videos: [FeedVideo]) {
        let keep = Set(videos.map(\.id))
        for (id, entry) in entries where !keep.contains(id) {
            entry.looper.disableLooping()
            entry.player.pause()
            entry.player.removeAllItems()
            entries[id] = nil
        }
        for video in videos where entries[video.id] == nil {
            let item = AVPlayerItem(url: video.hlsURL)
            item.preferredForwardBufferDuration = Self.forwardBufferDuration
            let player = AVQueuePlayer()
            player.automaticallyWaitsToMinimizeStalling = true
            player.defaultRate = rate
            entries[video.id] = Entry(player: player, looper: AVPlayerLooper(player: player, templateItem: item))
        }
        if let currentID, !keep.contains(currentID) { self.currentID = nil }
    }

    func play(_ videoID: String) {
        for (id, entry) in entries where id != videoID {
            entry.player.pause()
        }
        guard let player = entries[videoID]?.player else { return }
        if currentID != videoID {
            currentID = videoID
            player.seek(to: .zero)
        }
        player.play()
    }

    func pauseAll() {
        for entry in entries.values {
            entry.player.pause()
        }
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        for entry in entries.values {
            entry.player.defaultRate = rate
        }
        // La vidéo en cours (ou qui attend ses données pour jouer) change de vitesse aussitôt ; en pause, elle reste en pause.
        if let currentID, let player = entries[currentID]?.player, player.rate != 0 {
            player.rate = rate
        }
    }

    func progress(of videoID: String) -> PlaybackProgress? {
        guard let player = entries[videoID]?.player else { return nil }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds
        return PlaybackProgress(
            position: .seconds(position.isFinite ? max(0, position) : 0),
            duration: duration.flatMap { $0.isFinite && $0 > 0 ? .seconds($0) : nil }
        )
    }
}
