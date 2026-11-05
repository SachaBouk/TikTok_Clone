import CoreGraphics
import Foundation
import Observation

// Réglages du lecteur vidéo, un seul pour toute l'app (`AppContainer.playbackOptions`), valables pour toutes les vidéos du
// feed, des grilles et de la vidéo seule (lecteurs partagés) :
// - vitesse : appui long sur un côté (×2, verrouillable, `FastPlayback`) et vitesse du menu de la vidéo (ADR-067) ;
// - défilement automatique : à la fin d'une vidéo, la suivante (ADR-067) ;
// - affichage allégé : seule la vidéo reste, jusqu'au × (ADR-067).
// Vitesse et défilement automatique sont gardés jusqu'à la relance de l'app, et oubliés à la déconnexion (`reset`).
@MainActor
@Observable
final class PlaybackOptionsModel {
    private(set) var state = FastPlayback()
    // Message du haut (verrouillage, défilement automatique), effacé après `noticeDuration`.
    private(set) var notice: FastPlayback.Notice?
    // Hauteur, depuis le bas de l'écran, de ce qui est sous la vidéo (barre d'onglets) : recouvert de noir pendant l'appui,
    // avec le bandeau, comme TikTok.
    private(set) var bottomInset: CGFloat = 0
    private(set) var autoScroll = false
    private(set) var isClearMode = false
    // Doigt posé sur la barre de progression d'une vidéo : le balayage vers le profil de l'auteur est coupé.
    var isScrubbing = false

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
    var speed: PlaybackSpeed { state.speed }

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

    // Vitesse du menu de la vidéo, ou de la pastille de l'affichage allégé.
    func setSpeed(_ speed: PlaybackSpeed) {
        guard speed != state.speed else { return }
        state.setSpeed(speed)
        applyRate()
        analytics?.track(.playbackSpeedChanged(speed))
    }

    // Défilement automatique activé ou coupé (menu, ou bouton du message), avec son message.
    func setAutoScroll(_ enabled: Bool) {
        guard enabled != autoScroll else { return }
        autoScroll = enabled
        analytics?.track(.autoScrollChanged(enabled))
        show(enabled ? .autoScrollOn : .autoScrollOff)
    }

    // Affichage allégé : seule la vidéo reste ; quitté par le ×, en quittant le lecteur, à la déconnexion.
    func setClearMode(_ enabled: Bool) {
        guard enabled != isClearMode else { return }
        isClearMode = enabled
        analytics?.track(.clearModeChanged(enabled))
    }

    // Déconnexion : vitesse normale, sans défilement automatique ni affichage allégé.
    func reset() {
        state = FastPlayback()
        notice = nil
        autoScroll = false
        isClearMode = false
        noticeTask?.cancel()
        applyRate()
    }

    private func applyRate() {
        playback.setRate(state.rate)
    }

    private func show(_ notice: FastPlayback.Notice) {
        self.notice = notice
        // Lu à voix haute (ADR-076) : le message disparaît après 2 s.
        Accessibility.announce(notice.text)
        noticeTask?.cancel()
        noticeTask = Task { [noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled else { return }
            if self.notice == notice { self.notice = nil }
        }
    }
}
