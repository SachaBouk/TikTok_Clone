import Foundation
import Testing
import UIKit

@testable import TikTokClone

@MainActor
@Suite("Caméra, éditeur et brouillon (ADR-052)")
struct EditingTests {
    let store = InMemoryUploadStore()
    let analytics = FakeAnalyticsService()

    // MARK: Caméra

    @Test("démarrage : prête (avec ou sans son), refusée, indisponible")
    func cameraStart() async {
        let camera = FakeVideoCamera()
        camera.startResult = .ready(hasAudio: false)
        let model = CameraViewModel(kind: .video, camera: camera)
        #expect(model.status == .starting)
        await model.start()
        #expect(model.status == .ready)
        #expect(!model.hasAudio)
        #expect(camera.started == [.back])

        camera.startResult = .denied
        let denied = CameraViewModel(kind: .video, camera: camera)
        await denied.start()
        #expect(denied.status == .denied)
        #expect(!denied.canRecord)

        camera.startResult = .unavailable
        let unavailable = CameraViewModel(kind: .video, camera: camera)
        await unavailable.start()
        #expect(unavailable.status == .unavailable)
    }

    @Test("segments : durée restante demandée, segment trop bref ignoré, dernier retiré, limite atteinte")
    func cameraSegments() async throws {
        let camera = FakeVideoCamera()
        let model = CameraViewModel(kind: .story, camera: camera, now: { Date(timeIntervalSince1970: 100) })
        await model.start()

        model.shutterTapped()
        #expect(model.isRecording)
        #expect(camera.recordings == [.seconds(60)])
        #expect(!model.canSwitchCamera)
        #expect(!model.canFinish)
        #expect(abs(model.progress(at: Date(timeIntervalSince1970: 106)) - 0.1) < 0.000_001)
        model.shutterTapped()
        #expect(camera.stopRecordingCount == 1)
        let first = try temporaryClip(40)
        camera.finishSegment(.success(first))
        #expect(!model.isRecording)
        #expect(model.recording.segments == [first])

        model.shutterTapped()
        #expect(camera.recordings.last == .seconds(20))
        let tooShort = try temporaryClip(0.1)
        camera.finishSegment(.success(tooShort))
        #expect(model.recording.segments == [first])
        #expect(!exists(tooShort))

        model.shutterTapped()
        let second = try temporaryClip(20)
        camera.finishSegment(.success(second))
        #expect(model.recording.isFull)
        #expect(!model.canRecord)
        model.shutterTapped()
        #expect(camera.recordings.count == 3)

        model.removeLastSegment()
        #expect(!exists(second))
        #expect(model.canRecord)

        model.shutterTapped()
        camera.finishSegment(.failure(CocoaError(.fileWriteUnknown)))
        #expect(model.errorMessage == "L’enregistrement a échoué.")
        #expect(model.recording.segments == [first])

        let segments = try #require(model.finishRecording())
        #expect(segments == [first])
        #expect(exists(first))
        #expect(model.recording.segments.isEmpty)
        #expect(camera.stopCount == 1)
    }

    @Test("minuteur : 3 s avant l'enregistrement, annulé par un toucher")
    func cameraTimer() async {
        let camera = FakeVideoCamera()
        let model = CameraViewModel(kind: .video, camera: camera, sleep: { _ in })
        await model.start()
        model.timerEnabled = true
        model.shutterTapped()
        #expect(model.countdown == 3)
        await model.waitForCountdown()
        #expect(model.countdown == nil)
        #expect(model.isRecording)
        #expect(camera.recordings == [.seconds(180)])

        let slow = CameraViewModel(kind: .video, camera: FakeVideoCamera(), sleep: { try await Task.sleep(for: .seconds($0.seconds * 10)) })
        await slow.start()
        slow.timerEnabled = true
        slow.shutterTapped()
        #expect(slow.countdown == 3)
        slow.shutterTapped()
        await slow.waitForCountdown()
        #expect(slow.countdown == nil)
        #expect(!slow.isRecording)
    }

    @Test("caméra avant ou arrière, lampe à l'arrière seulement, abandon : segments supprimés")
    func cameraControls() async throws {
        let camera = FakeVideoCamera()
        let model = CameraViewModel(kind: .video, camera: camera)
        await model.start()
        #expect(model.canUseTorch)
        model.toggleTorch()
        #expect(model.torchOn)
        await model.switchCamera()
        #expect(model.position == .front)
        #expect(!model.torchOn)
        #expect(!model.canUseTorch)
        camera.switchSucceeds = false
        await model.switchCamera()
        #expect(model.position == .front)

        model.shutterTapped()
        let segment = try temporaryClip(5)
        camera.finishSegment(.success(segment))
        model.discard()
        #expect(!exists(segment))
        #expect(!model.hasSegments)
        #expect(model.captureModes == [.video])
    }

    @Test("story : photo prise par la caméra")
    func cameraPhoto() async {
        let camera = FakeVideoCamera()
        let model = CameraViewModel(kind: .story, camera: camera)
        await model.start()
        #expect(model.captureModes == [.video, .photo])
        #expect(await model.takePhoto() == Data("photo".utf8))
        camera.photo = .failure(CocoaError(.fileWriteUnknown))
        #expect(await model.takePhoto() == nil)
        #expect(model.errorMessage == "Impossible de prendre la photo.")
    }

    @Test("modes « Caméra » et « Story », durée choisie : seulement avant le premier segment")
    func cameraSettings() async throws {
        let camera = FakeVideoCamera()
        let model = CameraViewModel(kind: .video, camera: camera)
        await model.start()
        #expect(model.recording.maxDuration == .seconds(180))
        model.setLimit(.fifteenSeconds)
        #expect(model.limit == .fifteenSeconds && model.recording.maxDuration == .seconds(15))
        model.setKind(.story)
        #expect(model.kind == .story && model.recording.maxDuration == .seconds(60))
        #expect(model.captureModes == [.video, .photo])
        model.setLimit(.threeMinutes)
        #expect(model.limit == .fifteenSeconds)
        model.captureMode = .photo
        model.setKind(.video)
        #expect(model.captureMode == .video && model.recording.maxDuration == .seconds(15))

        model.shutterTapped()
        camera.finishSegment(.success(try temporaryClip(2)))
        #expect(model.hasSegments && !model.canChangeSettings)
        model.setKind(.story)
        model.setLimit(.sixtySeconds)
        #expect(model.kind == .video && model.limit == .fifteenSeconds)
        model.discard()
    }

    // MARK: Éditeur

    @Test("éditeur par clips : diviser, vitesse, volume, filtre relisent l'aperçu ; un geste = un pas d'annulation ; export")
    func editor() async throws {
        let editor = FakeVideoEditor(store: store)
        let clip = try temporaryClip(10)
        let model = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .camera),
            exportVideo: ExportEditedVideoUseCase(editor: editor), makeThumbnails: { _, times in Array(repeating: UIImage(), count: times.count) })
        let first = try #require(model.plan.clips.first)
        let key = model.thumbnailKey(for: first)
        #expect(key.count == 10)
        await model.loadThumbnails(key)
        #expect(model.thumbnails[key]?.count == 10)

        // Poignée de début, en un geste : un seul pas d'annulation.
        model.setStart(.seconds(1), of: first.id)
        model.setStart(.seconds(2), of: first.id)
        model.endInteraction()
        #expect(model.plan.clips[0].start == .seconds(2))
        #expect(model.previewVersion == 1)
        model.undo()
        #expect(model.plan.clips[0].start == .zero)
        model.redo()
        #expect(model.plan.clips[0].start == .seconds(2))

        // Diviser sous la tête de lecture : le second morceau est choisi.
        model.split(at: .seconds(3))
        #expect(model.plan.clips.count == 2)
        #expect(model.selectedClipID == model.plan.clips[1].id)
        model.setSpeed(2, applyToAll: false)
        model.endInteraction()
        #expect(model.plan.clips.map(\.speed) == [1, 2])
        model.setVolume(0, applyToAll: true)
        model.endInteraction()
        #expect(model.plan.clips.map(\.volume) == [0, 0])
        model.setFilter(.vintage)
        model.setFilter(.vintage)
        let version = model.previewVersion
        #expect(model.addText("Coucou", style: TextOverlay.Style(color: .red)))
        #expect(model.previewVersion == version)
        #expect(!model.addText(" "))
        #expect(model.errorMessage == "Écris un texte.")
        model.deleteSelectedClip()
        #expect(model.plan.clips.count == 1 && model.selectedClipID == nil)
        model.select(model.plan.clips[0].id)
        model.deleteSelectedClip()
        #expect(model.errorMessage == "La vidéo doit garder au moins un clip.")

        let result = try #require(await model.finish())
        // Il reste le premier morceau : de 2 s à 5 s.
        #expect(result.plan.outputDuration == .seconds(3))
        #expect(editor.exported == [result.plan])
        #expect(result.plan.texts.map(\.text) == ["Coucou"])
        #expect(exists(clip))
    }

    @Test("éditeur de texte : nouveau texte vide ignoré, ajouté avec son style, vidé = retiré ; pincer, glisser à la corbeille")
    func textEditing() throws {
        let editor = FakeVideoEditor(store: store)
        let clip = try temporaryClip(5)
        let model = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .camera),
            exportVideo: ExportEditedVideoUseCase(editor: editor), makeThumbnails: { _, _ in [] })
        model.finishEditingText(nil, text: "   ", style: TextOverlay.Style())
        #expect(model.plan.texts.isEmpty && model.errorMessage == nil && !model.canUndo)

        let style = TextOverlay.Style(color: .green, font: .technic, background: .solid)
        model.finishEditingText(nil, text: "motion", style: style)
        let text = try #require(model.plan.texts.first)
        #expect(text.text == "motion" && text.style == style)
        model.scaleText(text.id, to: 1.5)
        model.moveText(text.id, to: CGPoint(x: 0.5, y: 0.2))
        #expect(model.plan.texts[0].scale == 1.5 && model.plan.texts[0].center == CGPoint(x: 0.5, y: 0.2))
        model.undo()
        #expect(model.plan.texts[0].center == CGPoint(x: 0.5, y: 0.5) && model.plan.texts[0].scale == 1.5)

        model.finishEditingText(model.plan.texts[0], text: "motion !", style: TextOverlay.Style(color: .gray, background: .solid))
        #expect(model.plan.texts[0].text == "motion !" && model.plan.texts[0].style.color == .gray)
        // La position et la taille sont gardées.
        #expect(model.plan.texts[0].scale == 1.5)
        model.finishEditingText(model.plan.texts[0], text: "", style: style)
        #expect(model.plan.texts.isEmpty)
        model.undo()
        model.removeText(model.plan.texts[0].id)
        #expect(model.plan.texts.isEmpty)
    }

    @Test("filtres, autocollants, effets : intensité en un geste, autocollant daté, séance d'effets enregistrée en un pas")
    func looks() throws {
        let editor = FakeVideoEditor(store: store)
        let clip = try temporaryClip(6)
        let model = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .camera),
            exportVideo: ExportEditedVideoUseCase(editor: editor), makeThumbnails: { _, _ in [] })

        model.setFilter(.chill)
        let afterFilter = model.previewVersion
        model.setFilterIntensity(0.8)
        model.setFilterIntensity(0.3)
        model.endInteraction()
        #expect(model.plan.filterIntensity == 0.3 && model.previewVersion == afterFilter + 1)
        model.undo()
        #expect(model.plan.filterIntensity == 1 && model.plan.filter == .chill)

        // Autocollants : dessinés par SwiftUI, l'aperçu n'est pas relu.
        let version = model.previewVersion
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 16, minute: 42)))
        #expect(model.addSticker(.time, now: now))
        #expect(model.addSticker(.emoji, emoji: "🔥"))
        #expect(model.plan.stickers.map(\.text) == ["16:42", "🔥"] && model.previewVersion == version)
        let fire = model.plan.stickers[1]
        model.scaleSticker(fire.id, to: 2)
        model.moveSticker(fire.id, to: CGPoint(x: 0.3, y: 0.7))
        #expect(model.plan.stickers[1].scale == 2 && model.plan.stickers[1].center == CGPoint(x: 0.3, y: 0.7))
        model.removeSticker(fire.id)
        #expect(model.plan.stickers.count == 1)

        // Séance d'effets : annuler / rétablir dans la séance, puis un seul pas dans l'éditeur.
        let session = EffectsSession(effects: model.plan.effects, duration: model.plan.outputDuration)
        #expect(!session.hasChanges)
        #expect(session.add(.negative, at: .seconds(1)))
        let negative = try #require(session.selected)
        #expect(negative.start == .seconds(1) && negative.end == .seconds(3))
        session.setEnd(.seconds(4))
        session.setEnd(.seconds(5))
        session.endInteraction()
        #expect(session.effects[0].end == .seconds(5))
        session.undo()
        #expect(session.effects[0].end == .seconds(3))
        session.redo()
        session.add(.mirror, at: .seconds(5))
        session.removeSelected()
        #expect(session.effects.map(\.effect) == [.negative] && session.selected == nil && session.hasChanges)
        let beforeEffects = model.previewVersion
        model.setEffects(session.effects)
        #expect(model.plan.effects.count == 1 && model.previewVersion == beforeEffects + 1)
        model.undo()
        #expect(model.plan.effects.isEmpty)
    }

    @Test("éditeur : vidéos ajoutées par « + », supprimées à l'abandon ; clips retirés supprimés à l'export")
    func appendedClips() async throws {
        let clip = try temporaryClip(4)
        let added = try temporaryClip(3)
        let model = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .gallery, isNew: false),
            exportVideo: ExportEditedVideoUseCase(editor: FakeVideoEditor(store: store)), makeThumbnails: { _, _ in [] })
        model.append([added])
        #expect(model.plan.outputDuration == .seconds(7))
        model.discard()
        #expect(exists(clip) && !exists(added))

        let other = try temporaryClip(3)
        let exporting = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip, other], kind: .video), source: .gallery),
            exportVideo: ExportEditedVideoUseCase(editor: FakeVideoEditor(store: store)), makeThumbnails: { _, _ in [] })
        exporting.select(exporting.plan.clips[1].id)
        exporting.deleteSelectedClip()
        #expect(await exporting.finish() != nil)
        #expect(exists(clip) && !exists(other))
    }

    @Test("éditeur : vidéo trop longue bloquée, story de plus de 60 s refusée, export en échec, abandon d'une demande neuve")
    func editorProblems() async throws {
        let clip = try temporaryClip(200)
        let failing = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .gallery),
            exportVideo: ExportEditedVideoUseCase(editor: FakeVideoEditor(store: store, fails: true)), makeThumbnails: { _, _ in [] })
        #expect(failing.canFinish)
        #expect(failing.storyProblem == "Une story dure 60 secondes au plus. Raccourcis la vidéo.")
        failing.select(failing.plan.clips[0].id)
        failing.setSpeed(0.5, applyToAll: false)
        failing.endInteraction()
        #expect(!failing.canFinish)
        #expect(failing.problem == "Une vidéo dure 3 minutes au plus. Raccourcis-la.")
        #expect(await failing.finish() == nil)
        failing.undo()
        #expect(await failing.finish() == nil)
        #expect(failing.errorMessage == "Impossible de préparer cette vidéo.")

        let kept = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .gallery, isNew: false),
            exportVideo: ExportEditedVideoUseCase(editor: FakeVideoEditor(store: store)), makeThumbnails: { _, _ in [] })
        kept.discard()
        #expect(exists(clip))
        failing.discard()
        #expect(!exists(clip))
    }

    // MARK: Brouillon

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

    func makeDraft(_ publishing: PublishingModel, duration: Duration? = .seconds(12)) -> PublishDraftViewModel {
        PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), makePreview: { _ in nil },
            loadDuration: { _ in duration })
    }

    @Test("brouillon : segments filmés → éditeur → vidéo exportée → publication (source et modifications mesurées)")
    func recordedDraft() async throws {
        let publishing = await makePublishing()
        let draft = makeDraft(publishing)
        let segments = [try temporaryClip(4), try temporaryClip(3)]
        draft.recorded(segments)
        let request = try #require(draft.editorRequest)
        #expect(request.source == .camera && request.isNew)
        #expect(request.plan.sources == segments)
        #expect(!draft.canEdit)

        var plan = request.plan
        plan.filter = .mono
        plan.addText("Secret")
        let exported = store.addPickedFile("export.mov", Data("edited".utf8))
        await draft.edited(EditResult(file: exported, plan: plan), request: request)
        #expect(draft.editorRequest == nil)
        guard case .ready(let ready) = draft.state else {
            Issue.record("brouillon attendu")
            return
        }
        #expect(ready.file == exported && ready.duration == .seconds(7) && ready.source == .camera && ready.plan == plan)
        #expect(draft.canEdit)

        // Réouvrir l'éditeur repart des segments et du plan, sans les supprimer en cas d'abandon.
        draft.editCurrent()
        let again = try #require(draft.editorRequest)
        #expect(!again.isNew && again.plan == plan)
        draft.editorClosed()

        draft.description = "Ma vidéo"
        #expect(draft.publish())
        #expect(segments.allSatisfy { !exists($0) })
        #expect(publishing.publications.count == 1)
        let event = try #require(analytics.events.first { $0.name == "video_upload_started" })
        #expect(event.properties["source"] == .string("camera"))
        #expect(event.properties["segments"] == .int(2))
        #expect(event.properties["filter"] == .string("mono"))
        #expect(event.properties["text_count"] == .int(1))
    }

    @Test("brouillon : une nouvelle exportation remplace la précédente, l'abandon supprime tout")
    func reEditDraft() async throws {
        let publishing = await makePublishing()
        let draft = makeDraft(publishing)
        let segment = try temporaryClip(5)
        draft.recorded([segment])
        let request = try #require(draft.editorRequest)
        let firstExport = try temporaryClip(5)
        await draft.edited(EditResult(file: firstExport.file, plan: request.plan), request: request)
        draft.editCurrent()
        let second = try #require(draft.editorRequest)
        let secondExport = try temporaryClip(5)
        await draft.edited(EditResult(file: secondExport.file, plan: second.plan), request: second)
        #expect(!exists(firstExport))
        #expect(exists(segment))
        draft.discard()
        #expect(!exists(secondExport) && !exists(segment))
    }

    @Test("brouillon : une vidéo de la galerie ouvre toujours l'éditeur ; trop longue (ADR-040), avec le message")
    func galleryOpensEditor() async throws {
        let publishing = await makePublishing()
        let draft = makeDraft(publishing, duration: .milliseconds(181_500))
        await draft.load { store.addPickedFile("long.mov", Data("long".utf8)) }
        #expect(draft.state == .empty)
        let request = try #require(draft.editorRequest)
        #expect(request.source == .gallery && request.isNew)
        #expect(request.notice == "Cette vidéo dure plus de 3 minutes : choisis le passage à garder.")
        #expect(request.plan.clips[0].end == .seconds(180))
        #expect(request.plan.problem == nil)

        // À une seconde près : pas de message.
        let accepted = makeDraft(publishing, duration: .milliseconds(180_900))
        await accepted.load { store.addPickedFile("ok.mov", Data("ok".utf8)) }
        #expect(accepted.editorRequest?.notice == nil)
        #expect(accepted.editorRequest?.plan.isTrimmed == false)

        let story = makeDraft(publishing, duration: .seconds(75))
        story.mode = .story
        await story.load { store.addPickedFile("story.mov", Data("story".utf8)) }
        #expect(story.editorRequest?.notice == "Une story dure 60 secondes au plus : choisis le passage à garder.")
        #expect(story.editorRequest?.plan.clips.first?.end == .seconds(60))
    }

    @Test("brouillon : plusieurs vidéos de la galerie mises bout à bout ; une illisible fait tout échouer")
    func multipleGalleryVideos() async throws {
        let publishing = await makePublishing()
        let draft = makeDraft(publishing, duration: .seconds(5))
        await draft.loadVideos([{ store.addPickedFile("a.mov", Data("a".utf8)) }, { store.addPickedFile("b.mov", Data("b".utf8)) }])
        let request = try #require(draft.editorRequest)
        #expect(request.plan.clips.count == 2 && request.plan.outputDuration == .seconds(10))
        #expect(request.notice == nil)

        let unreadable = makeDraft(publishing, duration: nil)
        await unreadable.loadVideos([{ store.addPickedFile("c.mov", Data("c".utf8)) }, { store.addPickedFile("d.mov", Data("d".utf8)) }])
        #expect(unreadable.editorRequest == nil)
        #expect(unreadable.state == .failed("Impossible de lire cette vidéo."))
    }

    @Test("brouillon : « Ta story » depuis l'éditeur (60 s au plus), audience par défaut, commentaires envoyés")
    func storyAndSettings() async throws {
        let publishing = await makePublishing()
        let preferences = InMemoryPublishingPreferences()
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), preferences: preferences,
            makePreview: { _ in nil }, loadDuration: { _ in .seconds(5) })
        #expect(draft.visibility == .everyone && draft.commentsEnabled)

        // Story trop longue : refusée, le fichier exporté supprimé.
        let long = try temporaryClip(70)
        let tooLong = try temporaryClip(70)
        #expect(!draft.publishStory(EditResult(file: tooLong.file, plan: EditPlan(clips: [long], kind: .video)), source: .gallery))
        #expect(draft.errorMessage == "Une story dure 60 secondes au plus. Raccourcis la vidéo.")
        #expect(!exists(tooLong) && exists(long))

        let segment = try temporaryClip(8)
        let exported = store.addPickedFile("story.mov", Data("story".utf8))
        #expect(draft.publishStory(EditResult(file: exported, plan: EditPlan(clips: [segment], kind: .video)), source: .camera))
        #expect(!exists(segment))
        #expect(publishing.publications.first?.kind == .story)

        // Audience par défaut gardée ; réglages remis à zéro après la publication.
        draft.visibility = .onlyMe
        draft.makeVisibilityDefault()
        #expect(preferences.defaultVisibility == .onlyMe)
        draft.recorded([try temporaryClip(4)])
        let request = try #require(draft.editorRequest)
        await draft.edited(EditResult(file: store.addPickedFile("video.mov", Data("v".utf8)), plan: request.plan), request: request)
        #expect(draft.visibility == .onlyMe)
        draft.commentsEnabled = false
        #expect(draft.publish())
        let upload = try #require(store.uploads.first { $0.kind == .video })
        #expect(upload.visibility == .onlyMe && !upload.commentsEnabled)
        #expect(draft.visibility == .onlyMe && draft.commentsEnabled)
        let next = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), preferences: preferences)
        #expect(next.visibility == .onlyMe)
    }

    @Test("brouillon : « # Hashtags » ajoute un « # » à la fin de la description")
    func hashtagSign() async {
        let draft = makeDraft(await makePublishing())
        draft.insertHashtagSign()
        #expect(draft.description == "#")
        draft.description = "Coucou"
        draft.insertHashtagSign()
        #expect(draft.description == "Coucou #")
    }

    @Test("brouillon : photo de story prise par la caméra, mesurée comme telle")
    func cameraPhotoDraft() async {
        let publishing = await makePublishing()
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)),
            preparePhoto: PrepareStoryPhotoUseCase(renderer: FakeStoryPhotoRenderer(store: store)))
        draft.mode = .story
        await draft.loadMedia(source: .camera) { .photo(Data("photo".utf8)) }
        #expect(!draft.canEdit)
        #expect(draft.publish())
        let event = analytics.events.first { $0.name == "story_upload_started" }
        #expect(event?.properties == ["source": .string("camera"), "media_type": .string("photo")])
    }
}
