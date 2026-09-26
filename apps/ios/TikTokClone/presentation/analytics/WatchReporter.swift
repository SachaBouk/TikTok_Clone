import Foundation

// Mesure du visionnage (ADR-013) pour un écran de lecture (feed, liste, vidéo seule) : temps de lecture effectif,
// taux de complétion et moment du swipe, envoyés en `video_watched` quand la vidéo cesse d'être regardée.
// À appeler avant de lancer la vidéo suivante : la position de la précédente est lue au moment de la quitter.
@MainActor
final class WatchReporter {
    private let source: VideoSource
    private let playback: any VideoPlayback
    private let analytics: AnalyticsModel
    private let now: () -> Date
    private var timer = WatchTimer()
    private var video: FeedVideo?
    // Visionnage commencé avec le consentement : un visionnage commencé avant n'est pas envoyé.
    private var isMeasured = false

    init(source: VideoSource, playback: any VideoPlayback, analytics: AnalyticsModel, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.playback = playback
        self.analytics = analytics
        self.now = now
    }

    // La vidéo est lue : nouveau visionnage (le précédent se termine par un swipe), ou reprise après une pause.
    func play(_ video: FeedVideo) {
        if self.video?.id == video.id, timer.videoID == video.id {
            timer.resume(at: now())
            return
        }
        finish(.swipe)
        self.video = video
        isMeasured = analytics.isEnabled
        timer.start(video.id, at: now())
    }

    func pause() {
        timer.pause(at: now())
    }

    // Fin du visionnage en cours : envoyé s'il a duré.
    func finish(_ exit: WatchExit) {
        guard let video else { return }
        self.video = nil
        let progress = playback.progress(of: video.id)
        guard let result = timer.finish(at: now()), result.videoID == video.id, isMeasured else { return }
        analytics.track(.videoWatched(VideoWatch(
            videoID: video.id,
            authorID: video.author.id,
            source: source,
            watched: result.watched,
            duration: progress?.duration,
            exitPosition: progress?.position,
            exit: exit
        )))
    }

    // Vidéo supprimée pendant sa lecture : rien n'est envoyé.
    func discard() {
        video = nil
        _ = timer.finish(at: now())
    }
}
