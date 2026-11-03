import Testing

@testable import TikTokClone

@Suite("Vitesse ×2 du lecteur : règles")
struct FastPlaybackRulesTests {
    @Test("appui long : ×2 tant que le doigt reste posé, puis vitesse normale")
    func holdDoublesSpeed() {
        var fast = FastPlayback()
        #expect(fast.rate == 1)
        #expect(fast.hint == nil)
        fast.begin()
        #expect(fast.rate == 2)
        #expect(fast.hint == FastPlayback.Hint(text: "Glisse en bas pour garder la vitesse ×2", isArmed: false))
        #expect(fast.end() == nil)
        #expect(fast.rate == 1)
        #expect(!fast.isLocked)
    }

    @Test("glisser vers le bas puis relâcher verrouille la vitesse ×2")
    func swipeDownLocks() {
        var fast = FastPlayback()
        fast.begin()
        fast.drag(translation: 49)
        #expect(fast.hint?.isArmed == false)
        fast.drag(translation: 50)
        #expect(fast.hint == FastPlayback.Hint(text: "Relâche pour bloquer la vitesse ×2", isArmed: true))
        #expect(fast.end() == .locked)
        #expect(fast.isLocked)
        #expect(fast.rate == 2)
        #expect(FastPlayback.Notice.locked.text == "Verrouillée à la vitesse accélérée ×2")
    }

    @Test("remonter le doigt avant de relâcher ne verrouille pas")
    func swipeBackUpCancelsLock() {
        var fast = FastPlayback()
        fast.begin()
        fast.drag(translation: 80)
        fast.drag(translation: 10)
        #expect(fast.end() == nil)
        #expect(!fast.isLocked)
    }

    @Test("verrouillée : l'appui lit à vitesse normale, glisser vers le bas déverrouille")
    func unlock() {
        var fast = FastPlayback()
        fast.begin()
        fast.drag(translation: 60)
        fast.end()
        fast.begin()
        #expect(fast.rate == 1)
        #expect(fast.hint?.text == "Glisse en bas pour la vitesse normale")
        fast.drag(translation: 60)
        #expect(fast.hint?.text == "Relâche pour aller à vitesse normale")
        #expect(fast.end() == .unlocked)
        #expect(fast.rate == 1)
        #expect(FastPlayback.Notice.unlocked.text == "Retour à la vitesse normale")
    }

    @Test("verrouillée : un appui sans glisser garde le verrou")
    func lockedHoldKeepsLock() {
        var fast = FastPlayback()
        fast.begin()
        fast.drag(translation: 60)
        fast.end()
        fast.begin()
        #expect(fast.end() == nil)
        #expect(fast.isLocked)
        #expect(fast.rate == 2)
    }

    @Test("appui interrompu : rien ne change, même doigt descendu")
    func cancel() {
        var fast = FastPlayback()
        fast.begin()
        fast.drag(translation: 80)
        fast.cancel()
        #expect(!fast.isLocked)
        #expect(fast.rate == 1)
        #expect(fast.hint == nil)
    }

    @Test("seuls les côtés de la vidéo accélèrent, le milieu est réservé")
    func sides() {
        #expect(FastPlayback.isSide(x: 10, width: 400))
        #expect(FastPlayback.isSide(x: 119, width: 400))
        #expect(!FastPlayback.isSide(x: 120, width: 400))
        #expect(!FastPlayback.isSide(x: 200, width: 400))
        #expect(!FastPlayback.isSide(x: 280, width: 400))
        #expect(FastPlayback.isSide(x: 281, width: 400))
        #expect(!FastPlayback.isSide(x: 10, width: 0))
    }
}

@Suite("Vitesse ×2 du lecteur : modèle")
@MainActor
struct PlaybackOptionsModelTests {
    @Test("la vitesse suit l'appui et le verrou, sur les lecteurs partagés")
    func appliesRate() {
        let playback = FakePlayback()
        let model = PlaybackOptionsModel(playback: playback, analytics: nil)
        model.begin(bottomInset: 83)
        #expect(model.isHolding)
        #expect(model.bottomInset == 83)
        model.drag(translation: 60)
        model.end()
        #expect(!model.isHolding)
        #expect(model.isLocked)
        model.begin(bottomInset: 83)
        model.cancel()
        #expect(playback.rates == [2, 2, 1, 2])
    }

    @Test("verrouiller affiche un message un instant et le mesure")
    func noticeAndAnalytics() async throws {
        let service = FakeAnalyticsService()
        let model = PlaybackOptionsModel(playback: FakePlayback(), analytics: makeAnalytics(service), noticeDuration: .milliseconds(50))
        model.begin(bottomInset: 0)
        model.drag(translation: 60)
        model.end()
        #expect(model.notice == .locked)
        #expect(service.events.last == AnalyticsEvent(name: "playback_speed_locked", properties: ["locked": .bool(true)]))
        // Un nouvel appui efface le message.
        model.begin(bottomInset: 0)
        #expect(model.notice == nil)
        model.drag(translation: 60)
        model.end()
        #expect(model.notice == .unlocked)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.notice == nil)
    }

    @Test("déconnexion : retour à la vitesse normale")
    func reset() {
        let playback = FakePlayback()
        let model = PlaybackOptionsModel(playback: playback, analytics: nil)
        model.begin(bottomInset: 0)
        model.drag(translation: 60)
        model.end()
        model.reset()
        #expect(!model.isLocked)
        #expect(model.notice == nil)
        #expect(playback.rates.last == 1)
    }
}
