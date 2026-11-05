import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import TikTokClone

// Création accessible avec VoiceOver (ADR-076) : texte alternatif de la publication, phrases lues et équivalents des gestes
// de l'éditeur.
@MainActor
@Suite("Création accessible : texte alternatif, phrases et gestes de l'éditeur (ADR-076)")
struct AccessibleCreationTests {
    let store = InMemoryUploadStore()
    let analytics = FakeAnalyticsService()

    // MARK: Texte alternatif

    @Test("envoi : le texte alternatif part avec la vidéo (pas une story) ; un envoi enregistré avant n'en a pas")
    func altTextUpload() async throws {
        let videos = FakeVideoPublishingRepository()
        let upload = try CreatePublicationUseCase(store: store, makeID: { "u1" })(
            file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "", userID: "a",
            extras: PublicationExtras(altText: "Un chat saute sur une table"))
        #expect(upload.altText == "Un chat saute sur une table")
        let use = UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: FakePartTransport(), store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.extras(of: "vid-1") == UploadExtras(altText: "Un chat saute sur une table"))

        let story = try CreatePublicationUseCase(store: store, makeID: { "s1" })(
            file: store.addPickedFile("s.mov", Data("0123".utf8)), description: "", userID: "a", kind: .story,
            extras: PublicationExtras(altText: "Texte"))
        #expect(story.altText == nil)

        // Enregistré, puis relu : le texte reste ; un JSON d'avant l'ADR-076 n'en a pas.
        let reread = try JSONDecoder().decode(PendingUpload.self, from: JSONEncoder().encode(upload))
        #expect(reread.altText == "Un chat saute sur une table")
        let json = #"{"id":"u1","userID":"a","fileName":"f","contentType":"video/mp4","fileSize":1,"createdAt":0}"#
        #expect(try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8)).altText == nil)
    }

    @Test("écran : texte nettoyé à la publication, compté, mesuré (sans son contenu), remis à zéro ; trop long : pas de publication")
    func altTextPublish() async throws {
        let publishing = await makePublishing()
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), makePreview: { _ in nil },
            loadDuration: { _ in .seconds(8) })
        let clip = try temporaryClip(8)
        let request = EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .gallery)
        await draft.edited(EditResult(file: try exportedFile(), plan: request.plan), request: request)

        draft.altText = String(repeating: "a", count: AltTextRules.maxLength + 1)
        #expect(draft.altTextRemaining == -1 && !draft.canPublish)
        draft.altText = "  Une plage\nau coucher du soleil  "
        #expect(draft.altTextRemaining == AltTextRules.maxLength - "Une plage au coucher du soleil".count && draft.canPublish)
        #expect(draft.publish())
        let upload = try #require(store.uploads.first)
        #expect(upload.altText == "Une plage au coucher du soleil")
        let event = try #require(analytics.events.first { $0.name == "video_upload_started" })
        #expect(event.properties["alt_text"] == .bool(true))
        #expect(draft.altText.isEmpty)
    }

    @Test("brouillon : le texte alternatif est gardé ; un brouillon d'avant n'en a pas")
    func altTextDraft() throws {
        let plan = EditPlan(clips: [try temporaryClip(4)], kind: .video)
        let draft = VideoDraft(
            id: "d1", userID: "a", savedAt: Date(timeIntervalSince1970: 0), plan: plan, source: .camera, description: "", visibility: .everyone,
            commentsEnabled: true, soundShared: true, aiGenerated: false, location: nil, cover: CoverChoice(), downloadsEnabled: nil,
            altText: "Deux personnes dansent")
        let reread = try JSONDecoder().decode(VideoDraft.self, from: JSONEncoder().encode(draft))
        #expect(reread.altText == "Deux personnes dansent")
        var older = draft
        older.altText = nil
        #expect(try JSONDecoder().decode(VideoDraft.self, from: JSONEncoder().encode(older)).altText == nil)
        #expect(AltTextSpeech.summary("  ") == AltTextSpeech.explanation && AltTextSpeech.summary(" Un chat ") == "Un chat")
        #expect(AltTextSpeech.remaining(1) == "1 caractère restant" && AltTextSpeech.remaining(-3) == "3 caractères en trop")
    }

    // MARK: Phrases

    @Test("caméra : durées, segment filmé, segment supprimé")
    func cameraSpeech() {
        #expect(CameraSpeech.limit(.threeMinutes) == "3 minutes" && CameraSpeech.limit(.fifteenSeconds) == "15 secondes")
        #expect(CameraSpeech.recorded(.seconds(12), of: .seconds(180)) == "12 secondes filmées sur 3 minutes")
        #expect(CameraSpeech.segmentRecorded(.seconds(4), total: .seconds(12)) == "Segment de 4 secondes filmé, 12 secondes au total")
        #expect(CameraSpeech.segmentRemoved(total: .zero) == "Dernier segment supprimé, aucun segment")
        #expect(CameraSpeech.started(remaining: .seconds(168)) == "Enregistrement, 2 minutes 48 secondes restantes")
    }

    @Test("galerie : vidéo avec sa durée et sa date, numéro de sélection, compte")
    func gallerySpeech() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        let may = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 12))!
        let old = calendar.date(from: DateComponents(year: 2024, month: 5, day: 3, hour: 12))!
        #expect(GallerySpeech.label(isVideo: true, duration: .seconds(12), date: may, now: now, calendar: calendar) == "Vidéo, 12 secondes, 3 mai")
        #expect(GallerySpeech.label(isVideo: false, duration: nil, date: old, now: now, calendar: calendar) == "Photo, 3 mai 2024")
        #expect(GallerySpeech.label(isVideo: true, duration: .seconds(1), date: nil) == "Vidéo, 1 seconde")
        #expect(GallerySpeech.value(number: 2) == "Sélectionnée, numéro 2" && GallerySpeech.value(number: nil).isEmpty)
        #expect(GallerySpeech.selection(0) == "Aucune vidéo sélectionnée" && GallerySpeech.selection(3) == "3 vidéos sélectionnées")
    }

    @Test("éditeur par clips : phrase d'un clip, poignée, tête de lecture bornée")
    func clipSpeech() {
        #expect(
            ClipSpeech.label(index: 1, count: 3, duration: .milliseconds(4500), speed: 1.5, volume: 1, muted: true)
                == "Clip 2 sur 3, 4,5 secondes, vitesse 1,5 fois, son coupé")
        #expect(
            ClipSpeech.label(index: 0, count: 1, duration: .seconds(3), speed: 1, volume: 0.5, muted: false)
                == "Clip 1 sur 1, 3 secondes, volume 50 %")
        #expect(ClipSpeech.handle(.milliseconds(1200), of: .seconds(8)) == "1,2 seconde sur 8 secondes de la vidéo d'origine")
        #expect(ClipSpeech.playhead(.milliseconds(200), increment: false, total: .seconds(5)) == .zero)
        #expect(ClipSpeech.playhead(.milliseconds(4800), increment: true, total: .seconds(5)) == .seconds(5))
        #expect(ClipSpeech.playhead(.seconds(2), increment: true, total: .seconds(5)) == .milliseconds(2500))
        #expect(EditorValueSpeech.percent(0.326) == "33 %" && EditorValueSpeech.speed(2) == "2 fois")
    }

    @Test("textes et autocollants : libellés, position en mots, déplacements bornés, échelle bornée")
    func overlaySpeech() throws {
        #expect(OverlaySpeech.textLabel("Bonjour") == "Texte : Bonjour")
        #expect(OverlaySpeech.stickerLabel(kind: nil, text: "🔥") == "Autocollant : 🔥")
        #expect(OverlaySpeech.stickerLabel(kind: "Heure", text: "16:42") == "Autocollant : Heure 16:42")
        #expect(PlacementSpeech.region(CGPoint(x: 0.5, y: 0.5)) == "au centre")
        #expect(PlacementSpeech.region(CGPoint(x: 0.1, y: 0.1)) == "en haut à gauche")
        #expect(PlacementSpeech.region(CGPoint(x: 0.9, y: 0.5)) == "au milieu à droite")
        #expect(PlacementSpeech.region(CGPoint(x: 0.5, y: 0.9)) == "en bas au centre")
        #expect(OverlaySpeech.value(center: CGPoint(x: 0.5, y: 0.5), scale: 1.25) == "au centre, taille 125 %")

        let moved = OverlaySpeech.moved(CGPoint(x: 0.5, y: 0.5), .up)
        #expect(abs(moved.y - 0.45) < 0.0001 && moved.x == 0.5)
        #expect(OverlaySpeech.moved(CGPoint(x: 0.94, y: 0.5), .right).x == 0.95)
        #expect(OverlaySpeech.moved(CGPoint(x: 0.5, y: 0.06), .up).y == 0.05)
        #expect(OverlaySpeech.scaled(1, larger: true, range: TextOverlay.scaleRange) == 1.25)
        #expect(OverlaySpeech.scaled(2.8, larger: true, range: TextOverlay.scaleRange) == 3)
        #expect(OverlaySpeech.scaled(0.45, larger: false, range: TextOverlay.scaleRange) == 0.4)

        // Mêmes bornes que le plan : un texte déplacé par l'action reste où le plan le garde.
        var plan = EditPlan(clips: [SourceClip(file: URL(filePath: "/tmp/a.mov"), duration: .seconds(5))], kind: .video)
        let text = plan.addText("Salut")!
        plan.moveText(text.id, to: OverlaySpeech.moved(CGPoint(x: 0.95, y: 0.95), .down))
        #expect(plan.texts.first?.center == CGPoint(x: 0.95, y: 0.95))
    }

    @Test("recadrage : cadre décrit en mots ; déplacé sans sortir ; agrandi et réduit autour du centre, proportions gardées")
    func cropSpeech() {
        #expect(CropSpeech.value(.full, ratio: .free) == "Image entière")
        let square = CropRules.initial(ratio: .square, frameAspect: 9.0 / 16.0)
        #expect(CropSpeech.value(square, ratio: .square) == "Cadre 1:1, centré, 100 % de la largeur, 56 % de la hauteur")
        #expect(CropSpeech.ratio(.free) == "libres" && CropSpeech.ratio(.portrait) == "9:16")

        let top = CropSpeech.moved(square, .up)
        #expect(top.y < square.y && top.width == square.width)
        var atTop = square
        for _ in 0..<20 { atTop = CropSpeech.moved(atTop, .up) }
        #expect(atTop.y == 0)

        let smaller = CropSpeech.scaled(square, larger: false, ratio: .square, frameAspect: 9.0 / 16.0)
        #expect(smaller.width < square.width)
        // Proportions gardées (largeur relative / hauteur relative = 1:1 ramené à l'image en 9:16).
        #expect(abs(smaller.width / smaller.height - square.width / square.height) < 0.0001)
        // Centre gardé.
        #expect(abs((smaller.x + smaller.width / 2) - 0.5) < 0.0001 && abs((smaller.y + smaller.height / 2) - 0.5) < 0.0001)
        // Jamais au-delà de l'image.
        let larger = CropSpeech.scaled(square, larger: true, ratio: .square, frameAspect: 9.0 / 16.0)
        #expect(larger.width <= 1 && larger.height <= 1 && larger.x >= 0 && larger.y >= 0)
        // Jamais sous le côté minimal.
        var tiny = CropRect(x: 0.4, y: 0.4, width: 0.11, height: 0.11)
        tiny = CropSpeech.scaled(tiny, larger: false, ratio: .free, frameAspect: 1)
        #expect(tiny.width >= CropRules.minSize && tiny.height >= CropRules.minSize)
        // Libre, dans un coin : agrandi puis ramené dans l'image.
        let corner = CropSpeech.scaled(CropRect(x: 0, y: 0, width: 0.9, height: 0.9), larger: true, ratio: .free, frameAspect: 1)
        #expect(corner == CropRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test("effets : plage décrite, déplacée d'un bloc sans sortir de la vidéo ; voix off annoncée")
    func effectSpeech() {
        #expect(TimelineSpeech.range("Négatif", start: .seconds(2), end: .seconds(4)) == "Négatif, de 2 secondes à 4 secondes")
        #expect(TimelineSpeech.voiceoverRecorded(.milliseconds(3200)) == "Voix off enregistrée, 3,2 secondes")
        var track = EffectTrack(effects: [], duration: .seconds(5))
        let effect = track.add(.negative, at: .seconds(1), id: UUID())!
        track.move(effect.id, by: .seconds(10))
        #expect(track.effects.first?.start == .seconds(3) && track.effects.first?.end == .seconds(5))
        track.move(effect.id, by: .zero - .seconds(10))
        #expect(track.effects.first?.start == .zero && track.effects.first?.end == .seconds(2))
    }

    @Test("couverture, brouillon, son : phrases")
    func otherSpeech() {
        #expect(CoverSpeech.value(time: .seconds(3), duration: .seconds(10)) == "Image 4 sur 10, à 3 secondes")
        #expect(CoverSpeech.index(of: .seconds(9), duration: .seconds(10)) == 9)
        #expect(CoverSpeech.index(of: .seconds(20), duration: .seconds(10)) == 9)
        #expect(DraftSpeech.label(description: "", duration: .seconds(12)) == "Brouillon, 12 secondes")
        #expect(
            SoundSpeech.label(title: "Son original - @ines", author: "Inès", uses: 3, duration: .seconds(12))
                == "Son original - @ines, Inès, 3 publications, 12 secondes")
    }

    // MARK: Aides

    func makePublishing() async -> PublishingModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let videos = FakeVideoPublishingRepository()
        let stories = FakeStoryRepository()
        return PublishingModel(
            createPublication: CreatePublicationUseCase(store: store),
            uploadVideo: UploadVideoUseCase(videos: videos, stories: stories, transport: FakePartTransport(), store: store, retryDelays: []),
            pendingUploads: PendingUploadsUseCase(store: store),
            cancelUpload: CancelUploadUseCase(videos: videos, stories: stories, store: store),
            loadPendingVideos: LoadPendingVideosUseCase(videos: videos),
            loadVideo: LoadOwnVideoUseCase(videos: videos),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            loadStory: LoadOwnStoryUseCase(stories: stories),
            deleteStory: DeleteStoryUseCase(stories: stories),
            session: session,
            analytics: makeAnalytics(analytics),
            makePreview: { _ in nil },
            beginBackgroundWork: { {} }
        )
    }

    func exportedFile() throws -> URL {
        let file = URL.temporaryDirectory.appending(path: "export-\(UUID().uuidString).mov")
        try Data("edited".utf8).write(to: file)
        store.state.withLock { $0.picked[file] = Data("edited".utf8) }
        return file
    }
}
