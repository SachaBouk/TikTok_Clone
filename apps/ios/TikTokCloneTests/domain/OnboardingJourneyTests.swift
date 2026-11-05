import Testing

@testable import TikTokClone

@Suite("Onboarding animé : chemins et navigation (ADR-075)")
struct OnboardingJourneyTests {
    @Test("inscription : questions, inscription, tutoriels, consentement, paywall ; création seulement pour un créateur")
    func signupPath() {
        let watcher = OnboardingJourney.steps(path: .signup, goal: .watch, askConsent: true)
        #expect(
            watcher == [
                .welcome, .hello, .source, .goal, .preparing, .birthday, .email, .password, .username, .accountCreated, .interests,
                .swipeUp, .doubleTapLike, .fastForward, .swipeToProfile, .consent, .plus,
            ])
        let creator = OnboardingJourney.steps(path: .signup, goal: .create, askConsent: false)
        #expect(creator.contains(.create))
        #expect(!creator.contains(.consent))
        #expect(creator.last == .plus)
        #expect(creator.count >= 17)
    }

    @Test("connexion : ni questions, ni tutoriels, ni paywall ; invité : tutoriels sans paywall")
    func otherPaths() {
        #expect(OnboardingJourney.steps(path: .login, goal: nil, askConsent: true) == [.welcome, .login, .consent])
        #expect(OnboardingJourney.steps(path: .login, goal: nil, askConsent: false) == [.welcome, .login])
        let guest = OnboardingJourney.steps(path: .guest, goal: .both, askConsent: true)
        #expect(!guest.contains(.plus))
        #expect(!guest.contains(.interests))
        #expect(OnboardingJourney.step(after: .birthday, in: guest) == .swipeUp)
        #expect(guest.last == .consent)
        #expect(OnboardingJourney.steps(path: .replay, goal: .watch, askConsent: true) == OnboardingJourney.tutorials(goal: .watch))
    }

    @Test("feuille d'un invité : la fin commence aux tutoriels et finit au paywall")
    func promptFinale() {
        let finale = OnboardingJourney.finale(path: .promptSignup, goal: nil, askConsent: false)
        #expect(finale == [.swipeUp, .doubleTapLike, .fastForward, .swipeToProfile, .plus])
    }

    @Test("progression, retour, « Plus tard »")
    func navigationRules() {
        let steps = OnboardingJourney.steps(path: .signup, goal: .watch, askConsent: false)
        #expect(OnboardingJourney.progress(of: .welcome, in: steps) == 0)
        #expect(OnboardingJourney.progress(of: .plus, in: steps) == 1)
        #expect(OnboardingJourney.progress(of: .email, in: steps) < OnboardingJourney.progress(of: .password, in: steps))
        #expect(OnboardingJourney.step(after: .plus, in: steps) == nil)
        #expect(OnboardingJourney.canGoBack(from: .username))
        #expect(!OnboardingJourney.canGoBack(from: .accountCreated))
        #expect(!OnboardingJourney.canGoBack(from: .swipeUp))
        #expect(OnboardingJourney.offersGuestExit(.birthday, path: .signup))
        #expect(!OnboardingJourney.offersGuestExit(.birthday, path: .promptSignup))
        #expect(!OnboardingJourney.offersGuestExit(.interests, path: .signup))
        #expect(!OnboardingJourney.showsProgress(.login))
    }
}

@Suite("Sons synthétisés (ADR-075)")
struct ToneSynthTests {
    @Test("chaque son est court, non vide et ne sature pas")
    func samples() {
        for sound in UISound.allCases {
            let samples = ToneSynth.samples(for: sound)
            #expect(!samples.isEmpty, "\(sound)")
            #expect(Double(samples.count) / ToneSynth.sampleRate < 1.2, "\(sound)")
            #expect(samples.allSatisfy { abs($0) <= 1 }, "\(sound)")
            #expect(samples.contains { abs($0) > 0.01 }, "\(sound) muet")
        }
    }

    @Test("le son est le même à chaque fois (bruit déterministe)")
    func deterministic() {
        #expect(ToneSynth.samples(for: .whoosh) == ToneSynth.samples(for: .whoosh))
    }

    @Test("enveloppe : silence au début et à la fin d'une note")
    func envelope() {
        let note = ToneSynth.Note(from: 440, to: 440, start: 0, duration: 0.2)
        #expect(ToneSynth.envelope(time: 0, note: note) == 0)
        #expect(ToneSynth.envelope(time: 0.1, note: note) == 1)
        #expect(ToneSynth.envelope(time: 0.2, note: note) == 0)
    }
}
