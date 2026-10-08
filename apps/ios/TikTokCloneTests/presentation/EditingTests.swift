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

    // MARK: Éditeur

    @Test("éditeur : découpage, vitesse et filtre relisent l'aperçu ; export du plan")
    func editor() async throws {
        let editor = FakeVideoEditor(store: store)
        let clip = try temporaryClip(10)
        let model = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .camera),
            exportVideo: ExportEditedVideoUseCase(editor: editor), makeThumbnails: { _, count in Array(repeating: UIImage(), count: count) })
        await model.loadThumbnails(count: 4)
        #expect(model.thumbnails.count == 4)
        model.setTrimStart(fraction: 0.2)
        model.setTrimEnd(fraction: 0.8)
        #expect(model.plan.trimStart == .seconds(2) && model.plan.trimEnd == .seconds(8))
        #expect(abs(model.startFraction - 0.2) < 0.0001)
        model.setSpeed(.double)
        model.setFilter(.vintage)
        model.setFilter(.vintage)
        #expect(model.previewVersion == 4)
        #expect(model.addText("Coucou", color: .red, size: .small))
        #expect(model.previewVersion == 4)
        #expect(!model.addText(" ", color: .red, size: .small))
        #expect(model.errorMessage == "Écris un texte.")

        let result = try #require(await model.finish())
        #expect(result.plan.outputDuration == .seconds(3))
        #expect(editor.exported == [result.plan])
        #expect(result.plan.texts.map(\.text) == ["Coucou"])
    }

    @Test("éditeur : vidéo trop longue bloquée, export en échec, abandon d'une demande neuve")
    func editorProblems() async throws {
        let clip = try temporaryClip(200)
        let failing = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .gallery),
            exportVideo: ExportEditedVideoUseCase(editor: FakeVideoEditor(store: store, fails: true)), makeThumbnails: { _, _ in [] })
        #expect(failing.canFinish)
        failing.setSpeed(.half)
        #expect(!failing.canFinish)
        #expect(failing.problem == "Une vidéo dure 3 minutes au plus. Raccourcis-la.")
        #expect(await failing.finish() == nil)
        failing.setSpeed(.normal)
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
        #expect(request.plan.clips == segments)
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

    @Test("brouillon : vidéo de la galerie trop longue (ADR-040) → éditeur pour choisir le passage")
    func tooLongGallery() async throws {
        let publishing = await makePublishing()
        let draft = makeDraft(publishing, duration: .milliseconds(181_500))
        await draft.load { store.addPickedFile("long.mov", Data("long".utf8)) }
        #expect(draft.state == .empty)
        let request = try #require(draft.editorRequest)
        #expect(request.source == .gallery && request.isNew)
        #expect(request.notice == "Cette vidéo dure plus de 3 minutes : choisis le passage à garder.")
        #expect(request.plan.trimEnd == .seconds(180))
        #expect(request.plan.problem == nil)

        // À une seconde près : une vidéo de 3 min 0,9 s est acceptée telle quelle, modifiable ensuite.
        let accepted = makeDraft(publishing, duration: .milliseconds(180_900))
        await accepted.load { store.addPickedFile("ok.mov", Data("ok".utf8)) }
        #expect(accepted.canPublish)
        #expect(accepted.canEdit)
        #expect(accepted.editorRequest == nil)

        let story = makeDraft(publishing, duration: .seconds(75))
        story.mode = .story
        await story.load { store.addPickedFile("story.mov", Data("story".utf8)) }
        #expect(story.editorRequest?.notice == "Une story dure 60 secondes au plus : choisis le passage à garder.")
        #expect(story.editorRequest?.plan.trimEnd == .seconds(60))
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
