import CoreGraphics
import Foundation
import Observation

// Vitesse ×2 du lecteur vidéo (`FastPlayback`), une seule pour toute l'app (`AppContainer.fastPlayback`) : la vitesse
// verrouillée vaut pour toutes les vidéos du feed, des grilles et de la vidéo seule (lecteurs partagés). Gardée jusqu'à la
// relance de l'app ; oubliée à la déconnexion (`reset`).
@MainActor
@Observable
final class FastPlaybackModel {
    private(set) var state = FastPlayback()
    // Message du haut après un changement de verrouillage, effacé après `noticeDuration`.
    private(set) var notice: FastPlayback.Notice?
    // Hauteur, depuis le bas de l'écran, de ce qui est sous la vidéo (barre d'onglets) : recouvert de noir pendant l'appui,
    // avec le bandeau, comme TikTok.
    private(set) var bottomInset: CGFloat = 0

    private let playback: any VideoPlayback
    private let analytics: AnalyticsModel?
    private let noticeDuration: Duration
    private var noticeTask: Task<Void, Never>?

    init(playback: any VideoPlayback, analytics: AnalyticsModel?, noticeDuration: Duration = .seconds(2)) {
        self.playback = playback
        self.analytics = analytics
        self.noticeDuration = noticeDuration
    }

    // Appui en cours : auteur, description, boutons, barres du haut et barre d'onglets sont masqués.
    var isHolding: Bool { state.hold != nil }
    var isLocked: Bool { state.isLocked }

    func begin(bottomInset: CGFloat) {
        self.bottomInset = bottomInset
        state.begin()
        notice = nil
        applyRate()
    }

    func drag(translation: Double) {
        state.drag(translation: translation)
    }

    func end() {
        let notice = state.end()
        applyRate()
        guard let notice else { return }
        analytics?.track(.playbackSpeedLocked(notice == .locked))
        show(notice)
    }

    func cancel() {
        state.cancel()
        applyRate()
    }

    // Déconnexion : vitesse normale.
    func reset() {
        state = FastPlayback()
        notice = nil
        noticeTask?.cancel()
        applyRate()
    }

    private func applyRate() {
        playback.setRate(state.rate)
    }

    private func show(_ notice: FastPlayback.Notice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled else { return }
            if self.notice == notice { self.notice = nil }
        }
    }
}
