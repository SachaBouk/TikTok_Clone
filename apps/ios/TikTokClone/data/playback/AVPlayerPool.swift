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
        // Fin de chaque boucle (défilement automatique, ADR-067).
        let loops: NSKeyValueObservation
    }

    // Une vidéo est arrivée à sa fin (le lecteur repart au début) : le défilement automatique passe alors à la suivante.
    struct LoopEnd: Equatable {
        let videoID: String
        let count: Int
    }

    // Tampon réduit pour les vidéos préchargées : démarrage rapide sans télécharger toute la vidéo voisine.
    static let forwardBufferDuration: TimeInterval = 4

    private var entries: [String: Entry] = [:]
    private var currentID: String?
    // Vitesse de lecture (`FastPlayback`) : celle de chaque lecteur au démarrage (`defaultRate`).
    private var rate: Float = 1
    // Dernière fin de boucle d'une vidéo chargée.
    private(set) var lastLoopEnd: LoopEnd?

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
            entry.loops.invalidate()
            entry.player.removeAllItems()
            entries[id] = nil
        }
        for video in videos where entries[video.id] == nil {
            let item = AVPlayerItem(url: video.hlsURL)
            item.preferredForwardBufferDuration = Self.forwardBufferDuration
            let player = AVQueuePlayer()
            player.automaticallyWaitsToMinimizeStalling = true
            player.defaultRate = rate
            let looper = AVPlayerLooper(player: player, templateItem: item)
            let id = video.id
            let loops = looper.observe(\.loopCount, options: [.new]) { [weak self] looper, _ in
                let count = looper.loopCount
                guard count > 0 else { return }
                Task { @MainActor in self?.lastLoopEnd = LoopEnd(videoID: id, count: count) }
            }
            entries[video.id] = Entry(player: player, looper: looper, loops: loops)
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

    // Barre de progression de l'affichage allégé (ADR-067) : `fraction` de la vidéo, entre 0 et 1.
    func seek(_ videoID: String, to fraction: Double) {
        guard let player = entries[videoID]?.player, let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0
        else { return }
        let time = CMTime(seconds: min(1, max(0, fraction)) * duration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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
