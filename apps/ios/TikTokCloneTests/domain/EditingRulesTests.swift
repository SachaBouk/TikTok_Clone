import CoreGraphics
import Foundation
import Testing

@testable import TikTokClone

@Suite("Enregistrement et plan d'édition (ADR-052)")
struct EditingRulesTests {
    private func clip(_ name: String, _ seconds: Double) -> SourceClip {
        SourceClip(file: URL(filePath: "/tmp/\(name).mov"), duration: .milliseconds(Int64(seconds * 1000)))
    }

    @Test("segments : durée cumulée, restant, limite de 3 minutes ou 60 s, segment trop bref ignoré")
    func recordingSession() {
        var session = RecordingSession(kind: .video)
        #expect(session.maxDuration == .seconds(180))
        let appendedA = session.append(clip("a", 100))
        #expect(appendedA)
        let appendedShort = session.append(clip("bref", 0.2))
        #expect(!appendedShort)
        let appendedB = session.append(clip("b", 79.8))
        #expect(appendedB)
        #expect(session.recordedDuration == .milliseconds(179_800))
        #expect(session.remaining == .milliseconds(200))
        #expect(session.isFull)
        #expect(session.progress(including: .seconds(10)) == 1)
        let removedLast = session.removeLast()
        #expect(removedLast == clip("b", 79.8))
        #expect(!session.isFull)
        #expect(abs(session.progress() - 100.0 / 180.0) < 0.0001)
        let removedAll = session.removeAll()
        #expect(removedAll == [clip("a", 100)])
        #expect(session.segments.isEmpty)

        let story = RecordingSession(kind: .story)
        #expect(story.maxDuration == .seconds(60))
    }

    @Test("plan : intervalle de départ borné à la durée maximale, durée finale avec la vitesse")
    func initialTrimAndSpeed() {
        var plan = EditPlan(clips: [clip("a", 200), clip("b", 40)], kind: .video)
        #expect(plan.sourceDuration == .seconds(240))
        #expect(plan.trimStart == .zero)
        #expect(plan.trimEnd == .seconds(180))
        #expect(plan.isTrimmed)
        #expect(plan.problem == nil)
        plan.speed = .half
        #expect(plan.outputDuration == .seconds(360))
        #expect(plan.problem == "Une vidéo dure 3 minutes au plus. Raccourcis-la.")
        plan.speed = .double
        #expect(plan.outputDuration == .seconds(90))
        #expect(plan.problem == nil)

        let story = EditPlan(clips: [clip("s", 61.5)], kind: .story)
        #expect(story.trimEnd == .seconds(60))
        #expect(!EditPlan(clips: [clip("s", 30)], kind: .story).isTrimmed)
    }

    @Test("à une seconde près, comme le worker (ADR-040)")
    func tolerance() {
        #expect(!PublicationKind.video.isTooLong(.milliseconds(181_000)))
        #expect(PublicationKind.video.isTooLong(.milliseconds(181_001)))
        #expect(!PublicationKind.story.isTooLong(.seconds(61)))
        #expect(PublicationKind.story.isTooLong(.milliseconds(61_001)))
    }

    @Test("découpage : bornes dans la vidéo, au moins 1 s gardée")
    func trimBounds() {
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        plan.setTrimStart(.seconds(9.5))
        #expect(plan.trimStart == .seconds(9))
        plan.setTrimEnd(.seconds(2))
        #expect(plan.trimEnd == .seconds(10))
        plan.setTrimStart(.seconds(-3))
        #expect(plan.trimStart == .zero)
        plan.setTrimEnd(.seconds(4))
        #expect(plan.trimEnd == .seconds(4))
        plan.setTrimEnd(.seconds(50))
        #expect(plan.trimEnd == .seconds(10))

        let short = EditPlan(clips: [clip("court", 0.5)], kind: .video)
        #expect(short.problem == "La vidéo doit durer au moins 1 seconde.")
        #expect(EditPlan(clips: [], kind: .video).problem == "Aucune vidéo.")
    }

    @Test("réencodage seulement s'il le faut : assemblage, filtre, texte ou vitesse")
    func reencoding() {
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        #expect(!plan.needsReencoding)
        plan.setTrimStart(.seconds(2))
        #expect(!plan.needsReencoding)
        plan.filter = .mono
        #expect(plan.needsReencoding)
        plan.filter = .none
        plan.speed = .faster
        #expect(plan.needsReencoding)
        plan.speed = .normal
        plan.addText("Salut")
        #expect(plan.needsReencoding)
        #expect(EditPlan(clips: [clip("a", 1), clip("b", 1)], kind: .video).needsReencoding)
    }

    @Test("textes : nettoyés, 80 caractères et 5 au plus, déplacés dans l'image, vidés = retirés")
    func texts() throws {
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        let blank = plan.addText("   ")
        #expect(blank == nil)
        let tooLong = plan.addText(String(repeating: "a", count: 81))
        #expect(tooLong == nil)
        let added = plan.addText("  Bonjour  ", color: .yellow, size: .large)
        let first = try #require(added)
        #expect(first.text == "Bonjour")
        #expect(first.center == CGPoint(x: 0.5, y: 0.5))
        for index in 2...5 {
            let other = plan.addText("Texte \(index)")
            #expect(other != nil)
        }
        let sixth = plan.addText("Sixième")
        #expect(sixth == nil)

        plan.moveText(first.id, to: CGPoint(x: -1, y: 2))
        #expect(plan.texts[0].center == CGPoint(x: 0.05, y: 0.95))
        let updated = plan.updateText(first.id, text: "Salut", color: .red, size: .small)
        #expect(updated)
        #expect(plan.texts[0].text == "Salut" && plan.texts[0].color == .red && plan.texts[0].size == .small)
        let updatedTooLong = plan.updateText(first.id, text: String(repeating: "b", count: 81), color: .red, size: .small)
        #expect(!updatedTooLong)
        #expect(plan.texts[0].text == "Salut")
        let emptied = plan.updateText(first.id, text: "  ", color: .red, size: .small)
        #expect(!emptied)
        #expect(plan.texts.count == 4)
        plan.removeText(plan.texts[0].id)
        #expect(plan.texts.count == 3)
    }

    @Test("position dans les fichiers d'origine (miniatures de la frise)")
    func clipPosition() throws {
        let plan = EditPlan(clips: [clip("a", 4), clip("b", 6)], kind: .video)
        let start = try #require(plan.clipPosition(at: .seconds(1)))
        #expect(start.clip == clip("a", 4) && start.time == .seconds(1))
        let second = try #require(plan.clipPosition(at: .seconds(7)))
        #expect(second.clip == clip("b", 6) && second.time == .seconds(3))
        let end = try #require(plan.clipPosition(at: .seconds(12)))
        #expect(end.clip == clip("b", 6) && end.time == .seconds(6))
    }

    @Test("mesure d'audience : source et modifications, jamais le texte")
    func details() {
        var plan = EditPlan(clips: [clip("a", 10), clip("b", 5)], kind: .video)
        plan.setTrimEnd(.seconds(12))
        plan.filter = .warm
        plan.speed = .faster
        plan.addText("Secret")
        let properties = PublicationDetails(source: .camera, plan: plan).properties(photo: false)
        #expect(
            properties == [
                "source": .string("camera"), "segments": .int(2), "trimmed": .bool(true), "filter": .string("warm"), "text_count": .int(1),
                "speed": .double(1.5),
            ])
        #expect(PublicationDetails().properties(photo: true) == ["source": .string("gallery")])
        let story = AnalyticsEvent.storyUploadStarted(photo: true, details: PublicationDetails(source: .camera))
        #expect(story.properties == ["source": .string("camera"), "media_type": .string("photo")])
        let video = AnalyticsEvent.uploadStarted(PublicationDetails())
        #expect(video.name == "video_upload_started")
        #expect(video.properties["segments"] == .int(1) && video.properties["trimmed"] == .bool(false))
    }
}
