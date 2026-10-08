import Foundation
import Testing
import UIKit

@testable import TikTokClone

@MainActor
@Suite("Publication : modèle partagé et brouillon")
struct PublishingModelTests {
    let videos = FakeVideoPublishingRepository()
    let stories = FakeStoryRepository()
    let transport = FakePartTransport()
    let store = InMemoryUploadStore()

    func makeModel(signedIn: Bool = true) async -> (PublishingModel, SessionStore) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        let model = PublishingModel(
            createPublication: CreatePublicationUseCase(store: store),
            uploadVideo: UploadVideoUseCase(videos: videos, stories: stories, transport: transport, store: store, retryDelays: []),
            pendingUploads: PendingUploadsUseCase(store: store),
            cancelUpload: CancelUploadUseCase(videos: videos, stories: stories, store: store),
            loadPendingVideos: LoadPendingVideosUseCase(videos: videos),
            loadVideo: LoadOwnVideoUseCase(videos: videos),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            loadStory: LoadOwnStoryUseCase(stories: stories),
            deleteStory: DeleteStoryUseCase(stories: stories),
            session: session,
            analytics: makeAnalytics(),
            makePreview: { _ in nil },
            beginBackgroundWork: { {} }
        )
        return (model, session)
    }

    func picked(_ name: String = "clip.mov") -> URL {
        store.addPickedFile(name, Data("0123456789".utf8))
    }

    @Test("publier : envoi, confirmation, puis traitement ; badge tant que ce n'est pas fini")
    func publish() async {
        let (model, _) = await makeModel()
        #expect(model.publish(file: picked(), description: " Salut ", preview: nil) == nil)
        #expect(model.publications.first?.description == "Salut")
        #expect(await eventually { model.publications.first?.phase == .processing })
        #expect(model.publications.first?.videoID == "vid-1")
        #expect(model.inProgressCount == 1)
        #expect(videos.completed("vid-1")?.count == 3)
        #expect(store.uploads.isEmpty)

        model.videoProcessed(
            OwnVideo(id: "vid-1", description: "Salut", status: .ready, thumbnailURL: URL(string: "http://cdn.test/t.jpg"), createdAt: .now))
        #expect(model.publications.first?.phase == .ready)
        #expect(model.publications.first?.thumbnailURL?.absoluteString == "http://cdn.test/t.jpg")
        #expect(model.inProgressCount == 0)
        model.dismiss(model.publications[0].id)
        #expect(model.publications.isEmpty)
    }

    @Test("format refusé : message, rien n'est envoyé")
    func publishRejected() async {
        let (model, _) = await makeModel()
        #expect(model.publish(file: picked("clip.avi"), description: "", preview: nil) != nil)
        #expect(model.publications.isEmpty)
    }

    @Test("coupure : envoi interrompu avec un message ; « Réessayer » reprend à la partie suivante")
    func interruptedThenRetry() async {
        let (model, _) = await makeModel()
        transport.state.withLock { $0.errors = [AppError.network] }
        _ = model.publish(file: picked(), description: "", preview: nil)
        #expect(await eventually { model.publications.first?.phase == .interrupted(AppError.network.message) })
        #expect(store.uploads.first?.ticket?.videoID == "vid-1")

        model.retry(model.publications[0].id)
        #expect(await eventually { model.publications.first?.phase == .processing })
        #expect(videos.created == ["vid-1"])
    }

    @Test("retour au premier plan : un envoi coupé par le réseau reprend seul")
    func resumesWhenActive() async {
        let (model, _) = await makeModel()
        transport.state.withLock { $0.errors = [AppError.network] }
        _ = model.publish(file: picked(), description: "", preview: nil)
        #expect(await eventually { if case .interrupted = model.publications.first?.phase { true } else { false } })
        await model.update(signedIn: true, active: true)
        #expect(await eventually { model.publications.first?.phase == .processing })
    }

    @Test("relance de l'app : envois enregistrés repris, vidéos en traitement et en échec relues")
    func refreshAfterRelaunch() async throws {
        let file = picked()
        _ = try CreatePublicationUseCase(store: store)(file: file, description: "Reprise", userID: UserProfile.alice.id)
        let failed = OwnVideo(id: "old", description: nil, status: .failed, thumbnailURL: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        videos.state.withLock { $0.pending = [failed] }

        let (model, _) = await makeModel()
        await model.refresh()
        #expect(await eventually { model.publications.map(\.phase) == [.processing, .failed] })
        #expect(model.publications.map(\.description) == ["Reprise", nil])
    }

    @Test("vidéo suivie publiée pendant une coupure : relue à la reconnexion")
    func processingFinishedWhileOffline() async {
        let (model, _) = await makeModel()
        _ = model.publish(file: picked(), description: "", preview: nil)
        #expect(await eventually { model.publications.first?.phase == .processing })
        videos.state.withLock { $0.videos["vid-1"] = OwnVideo(id: "vid-1", description: nil, status: .ready, thumbnailURL: nil, createdAt: .now) }
        await model.refresh()
        #expect(model.publications.first?.phase == .ready)
    }

    @Test("supprimer une vidéo en échec ; annuler un envoi en cours")
    func delete() async {
        let failed = OwnVideo(id: "old", description: nil, status: .failed, thumbnailURL: nil, createdAt: .now)
        videos.state.withLock {
            $0.pending = [failed]
            $0.videos["old"] = failed
        }
        let (model, _) = await makeModel()
        await model.refresh()
        #expect(await model.delete("old") == nil)
        #expect(videos.deleted == ["old"])
        #expect(model.publications.isEmpty)

        transport.state.withLock { $0.delay = .seconds(5) }
        _ = model.publish(file: picked(), description: "", preview: nil)
        #expect(await eventually { if case .uploading = model.publications.first?.phase { true } else { false } })
        #expect(await model.delete(model.publications[0].id) == nil)
        #expect(model.publications.isEmpty)
        #expect(store.uploads.isEmpty)
        #expect(videos.deleted == ["old", "vid-1"])
    }

    @Test("déconnexion : liste vidée, l'envoi reste enregistré pour ce compte")
    func signOut() async {
        let (model, _) = await makeModel()
        transport.state.withLock { $0.delay = .seconds(5) }
        _ = model.publish(file: picked(), description: "", preview: nil)
        await model.update(signedIn: false, active: true)
        #expect(model.publications.isEmpty)
        #expect(store.uploads.count == 1)
    }

    @Test("brouillon : chargement, compteur de caractères, publication")
    func draft() async {
        let (model, _) = await makeModel()
        let cleaner = FakeVideoMetadataCleaner(store: store)
        let draft = PublishDraftViewModel(
            publishing: model, prepareVideo: PrepareVideoUseCase(cleaner: cleaner), makePreview: { _ in nil }, loadDuration: { _ in .seconds(12) }
        )
        #expect(!draft.canPublish)
        let file = picked()
        await draft.load { file }
        // C'est le fichier nettoyé qui est gardé, puis envoyé ; l'original a disparu.
        let cleaned = file.deletingPathExtension().appendingPathExtension("clean.mov")
        #expect(cleaner.cleaned == [file])
        #expect(store.state.withLock { $0.picked[file] } == nil)
        #expect(
            draft.state
                == .ready(.init(file: cleaned, preview: nil, duration: .seconds(12), sources: [SourceClip(file: cleaned, duration: .seconds(12))])))
        draft.description = String(repeating: "a", count: 2201)
        #expect(draft.remainingCharacters == -1)
        #expect(!draft.canPublish)
        draft.description = "Ma vidéo"
        #expect(draft.publish())
        #expect(draft.state == .empty)
        #expect(draft.description.isEmpty)
        #expect(model.publications.count == 1)

        await draft.load { throw URLError(.cancelled) }
        #expect(draft.state == .failed("Impossible d’importer cette vidéo."))
    }

    @Test("brouillon : plus de 3 minutes (ADR-040) jamais envoyée telle quelle (éditeur, ADR-052), à une seconde près")
    func draftTooLong() async {
        let (model, _) = await makeModel()
        let cleaner = FakeVideoMetadataCleaner(store: store)
        var duration: Duration = .milliseconds(181_500)
        let draft = PublishDraftViewModel(
            publishing: model, prepareVideo: PrepareVideoUseCase(cleaner: cleaner), makePreview: { _ in nil },
            loadDuration: { [duration] _ in duration }
        )
        await draft.load { picked() }
        #expect(draft.state == .empty)
        #expect(draft.editorRequest?.plan.trimEnd == .seconds(180))
        #expect(!draft.canPublish)
        #expect(model.publications.isEmpty)

        duration = .milliseconds(180_900)
        let accepted = PublishDraftViewModel(
            publishing: model, prepareVideo: PrepareVideoUseCase(cleaner: cleaner), makePreview: { _ in nil },
            loadDuration: { [duration] _ in duration }
        )
        await accepted.load { picked() }
        #expect(accepted.canPublish)
        #expect(UploadRules.isTooLong(.seconds(182)))
        #expect(!UploadRules.isTooLong(.seconds(180)))
    }

    @Test("brouillon : une vidéo qu'on ne sait pas nettoyer est refusée, rien n'est gardé")
    func draftCleaningFails() async {
        let (model, _) = await makeModel()
        let draft = PublishDraftViewModel(
            publishing: model, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store, fails: true)),
            makePreview: { _ in nil }, loadDuration: { _ in nil }
        )
        let file = picked()
        await draft.load { file }
        #expect(draft.state == .failed("Impossible de préparer cette vidéo."))
        #expect(!draft.canPublish)
        #expect(store.state.withLock { $0.picked.isEmpty })
        #expect(model.publications.isEmpty)
    }
}
