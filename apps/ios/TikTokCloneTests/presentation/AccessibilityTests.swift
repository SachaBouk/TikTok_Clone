import Foundation
import SwiftUI
import Synchronization
import Testing

@testable import TikTokClone

// Accessibilité VoiceOver (ADR-076) : phrases lues, description automatique, texte alternatif.
@MainActor
@Suite("Accessibilité VoiceOver")
struct AccessibilityTests {
    @Test("nombres en entier, singulier jusqu'à 1, durées et positions parlées")
    func spokenText() {
        #expect(SpokenText.number(1200) == "1\u{202F}200" || SpokenText.number(1200) == "1\u{00A0}200")
        #expect(SpokenText.count(1, "abonné", "abonnés") == "1 abonné")
        #expect(SpokenText.count(0, "vue", "vues") == "0 vue")
        #expect(SpokenText.count(2, "vue", "vues") == "2 vues")
        #expect(SpokenText.duration(1) == "1 seconde")
        #expect(SpokenText.duration(4.5) == "4,5 secondes")
        #expect(SpokenText.duration(0.04) == "0 seconde")
        #expect(SpokenText.duration(65) == "1 minute 5 secondes")
        #expect(SpokenText.duration(180) == "3 minutes")
        #expect(SpokenText.position(5, of: 24) == "5 secondes sur 24 secondes")
        #expect(SpokenText.ordinal(1, of: 5) == "2 sur 5")
        #expect(SpokenText.join(["a", nil, " ", "b"]) == "a, b")
        #expect(SpeedSpeech.text(2) == "2 fois")
        #expect(SpeedSpeech.text(1.5) == "1,5 fois")
    }

    @Test("vidéo : l'état d'abord ; le texte de l'auteur l'emporte sur la description automatique")
    func videoSpeech() {
        var speech = VideoSpeech(author: "alice", description: "Plage #été", autoDescription: "Description automatique : peut contenir la mer")
        #expect(speech.label == "Vidéo de @alice")
        #expect(speech.value(isPlaying: true) == "En lecture, Plage #été, Description automatique : peut contenir la mer")
        #expect(speech.arrival == "@alice : Plage #été, Description automatique : peut contenir la mer")
        speech.altText = "Un chien court sur le sable"
        speech.locationName = "Biarritz"
        speech.aiGenerated = true
        speech.isPrivate = true
        #expect(
            speech.value(isPlaying: false, speed: 2)
                == "En pause, Toi uniquement, Plage #été, Description de la vidéo : Un chien court sur le sable, Lieu : Biarritz, Créé avec l'IA")
        #expect(speech.value(isPlaying: true, speed: 2).hasPrefix("En lecture, vitesse 2 fois"))
        #expect(VideoSpeech(author: "bob").arrival == "Vidéo de @bob")
    }

    @Test("message : qui, quoi et quand")
    func messageSpeech() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 15)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14, minute: 32)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9, minute: 5)))
        let older = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9, minute: 5)))
        #expect(MessageSpeech.label(sender: nil, isOwn: true, content: "salut", sentAt: today, now: now, calendar: calendar) == "Toi : salut, 14:32")
        #expect(
            MessageSpeech.label(sender: "Inès", isOwn: false, content: "ok", sentAt: yesterday, now: now, calendar: calendar)
                == "Inès : ok, hier, 09:05")
        #expect(MessageSpeech.time(older, now: now, calendar: calendar) == "2 octobre 2026, 09:05")
    }

    @Test("description automatique : visages, scènes traduites, texte ; rien à dire : nil")
    func autoDescription() {
        #expect(AutoDescription.text(ImageAnalysis(faces: 0, sceneIdentifiers: [], recognizedText: nil)) == nil)
        #expect(AutoDescription.text(ImageAnalysis(faces: 0, sceneIdentifiers: ["unknown_thing"], recognizedText: "  ")) == nil)
        #expect(
            AutoDescription.text(ImageAnalysis(faces: 2, sceneIdentifiers: ["people", "beach", "dog", "sky", "tree"], recognizedText: nil))
                == "Description automatique : peut contenir 2 personnes, une plage, un chien, le ciel")
        #expect(
            AutoDescription.text(ImageAnalysis(faces: 1, sceneIdentifiers: [], recognizedText: "SOLDES\n-50 %"))
                == "Description automatique : peut contenir une personne. texte : « SOLDES -50 % »")
        let long = String(repeating: "a", count: 200)
        let text = AutoDescription.text(ImageAnalysis(faces: 0, sceneIdentifiers: [], recognizedText: long)) ?? ""
        #expect(text.hasSuffix("… »"))
    }

    @Test("texte alternatif : nettoyé comme l'API, 300 caractères au plus")
    func altTextRules() {
        #expect(AltTextRules.cleaned("  Un  chat\n saute ") == "Un chat saute")
        #expect(AltTextRules.cleaned("   ") == nil)
        #expect(AltTextRules.cleaned(nil) == nil)
        #expect(!AltTextRules.isTooLong(String(repeating: "a", count: 300)))
        #expect(AltTextRules.isTooLong(String(repeating: "a", count: 301)))
    }

    @Test("liens d'une description proposés en actions, sans doublon")
    func links() {
        let links = VideoLinks(description: "#Été avec @ines et @ines #été #plage")
        #expect(links.hashtags == ["été", "plage"])
        #expect(links.mentions == ["ines"])
        #expect(VideoLinks(description: nil) == VideoLinks(description: ""))
    }

    @Test("barre de progression : ± 5 s, bornée à la vidéo")
    func progress() {
        let progress = PlaybackProgress(position: .seconds(3), duration: .seconds(20))
        #expect(AccessibleProgress.target(progress, direction: .increment) == 8.0 / 20)
        #expect(AccessibleProgress.target(progress, direction: .decrement) == 0)
        #expect(AccessibleProgress.target(PlaybackProgress(position: .seconds(18), duration: .seconds(20)), direction: .increment) == 1)
        #expect(AccessibleProgress.target(PlaybackProgress(position: .zero, duration: nil), direction: .increment) == nil)
        #expect(AccessibleProgress.value(progress) == "3 secondes sur 20 secondes")
        #expect(AccessibleProgress.value(nil) == "Chargement")
    }

    @Test("description automatique : seulement avec VoiceOver, sans texte de l'auteur, une fois par vidéo")
    func autoDescriptionModel() async throws {
        let describer = CountingDescriber()
        var voiceOver = false
        let model = AutoDescriptionModel(describe: DescribeImageUseCase(describer: describer), isVoiceOverRunning: { voiceOver })
        let video = FeedVideo.sample("v1")
        model.prepare(video)
        try await Task.sleep(for: .milliseconds(50))
        #expect(describer.calls.withLock { $0 } == 0)

        voiceOver = true
        model.prepare(video)
        model.prepare(video)
        var described = video
        described.altText = "Écrit par l'auteur"
        model.prepare(FeedVideo.sample("v2").withAltText("Écrit"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(describer.calls.withLock { $0 } == 1)
        #expect(model.description(for: video) == "Description automatique : peut contenir un chat")
        #expect(model.description(for: described) == nil)
    }

    @Test("texte alternatif changé par l'auteur : nettoyé, affiché, trop long refusé ; vidéo d'un autre : rien")
    func setAltText() async {
        let repository = FakeAltTextRepository()
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: FakeInteractionRepository()),
            setFollow: SetFollowUseCase(interactions: FakeInteractionRepository()),
            recordShare: ShareVideoUseCase(interactions: FakeInteractionRepository()),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            setAltText: SetVideoAltTextUseCase(videos: repository),
            session: session,
            analytics: makeAnalytics()
        )
        let mine = FeedVideo.sample("v1", author: "alice").byAlice
        #expect(await interactions.setAltText("  Un chat  roux ", of: mine) == nil)
        #expect(interactions.display(mine).altText == "Un chat roux")
        #expect(repository.saved.withLock { $0 } == ["v1": "Un chat roux"])
        #expect(await interactions.setAltText(String(repeating: "a", count: 301), of: mine) != nil)
        #expect(await interactions.setAltText("", of: mine) == nil)
        #expect(interactions.display(mine.withAltText("Ancien")).altText == nil)
        #expect(await interactions.setAltText("x", of: FeedVideo.sample("v2")) == nil)
        #expect(repository.saved.withLock { $0 }["v2"] == nil)
    }
}

private final class CountingDescriber: ImageDescriber {
    let calls = Mutex(0)
    func analyze(imageAt url: URL) async throws -> ImageAnalysis {
        calls.withLock { $0 += 1 }
        return ImageAnalysis(faces: 0, sceneIdentifiers: ["cat"], recognizedText: nil)
    }
}

private final class FakeAltTextRepository: VideoAltTextRepository {
    let saved = Mutex<[String: String?]>([:])
    func setAltText(videoID: String, altText: String?) async throws {
        saved.withLock { $0[videoID] = altText }
    }
}

extension FeedVideo {
    fileprivate func withAltText(_ text: String?) -> FeedVideo {
        var copy = self
        copy.altText = text
        return copy
    }
}
