import Foundation
import Synchronization
import Testing
import UIKit

@testable import TikTokClone

// Enregistrement dans Photos de test : autorisation choisie, vidéos « copiées » gardées.
final class FakePhotoLibrarySaver: PhotoLibrarySaver {
    let granted: Bool
    let saved = Mutex<[URL]>([])

    init(granted: Bool) { self.granted = granted }

    func requestAddAccess() async -> Bool { granted }
    func saveVideo(_ file: URL) async throws { saved.withLock { $0.append(file) } }
}

// Recherche de lieux de test : résultats par texte, lieux proches, autorisation demandée.
@MainActor
final class FakePlaceSearch: PlaceSearch {
    var locationAccess: LocationAccess = .notDetermined
    var grant: LocationAccess = .authorized
    var results: [String: [VideoLocation]] = [:]
    var nearbyPlaces: [VideoLocation] = []
    private(set) var queries: [String] = []

    func requestLocationAccess() async -> LocationAccess {
        locationAccess = grant
        return grant
    }

    func search(_ text: String) async throws -> [VideoLocation] {
        queries.append(text)
        return results[text] ?? []
    }

    func nearby() async throws -> [VideoLocation] { nearbyPlaces }
}

@MainActor
@Suite("Écran de publication : couverture, lieu, mentions, brouillons (ADR-065)")
struct PublicationScreenTests {
    let store = InMemoryUploadStore()
    let analytics = FakeAnalyticsService()

    // MARK: Règles

    @Test("couverture : choisie si une autre image ou un titre ; titre borné ; images de la frise ; instant ramené")
    func coverRules() {
        var cover = CoverChoice()
        #expect(!cover.isCustom && cover.shownTitle == nil)
        cover.setTitle("  ")
        cover.style = .skew
        #expect(!cover.isCustom)
        cover.setTitle(String(repeating: "a", count: 80) + "\n")
        #expect(cover.title.count == CoverChoice.maxTitleLength && cover.isCustom)
        cover.style = nil
        #expect(cover.shownTitle == nil && !cover.isCustom)
        cover.time = .seconds(9)
        let clamped = cover.clamped(to: .seconds(5))
        #expect(cover.isCustom && clamped.time == .milliseconds(4900))

        let times = CoverChoice.frameTimes(duration: .seconds(10))
        #expect(times.count == 10 && times.first == .zero && times.last == .seconds(9))
        #expect(CoverChoice.time(atFraction: 0.5, duration: .seconds(10)) == .seconds(5))
        #expect(CoverChoice.time(atFraction: 2, duration: .seconds(10)) < .seconds(10))
    }

    @Test("lieu : nom et adresse ramenés aux longueurs de l'API, adresse vide retirée")
    func locationBounds() {
        let long = VideoLocation(name: String(repeating: "n", count: 150), address: String(repeating: "a", count: 300)).bounded
        #expect(long.name.count == 100 && long.address?.count == 200)
        #expect(VideoLocation(name: "Parc", address: "").bounded.address == nil)
    }

    // MARK: Envoi

    @Test("envoi : couverture adoptée puis envoyée (image/jpeg) avant la confirmation ; étiquette IA et lieu transmis")
    func uploadExtras() async throws {
        let videos = FakeVideoPublishingRepository()
        let transport = FakePartTransport()
        let create = CreatePublicationUseCase(store: store, makeID: { "u1" })
        let cover = store.addPickedFile("cover.jpg", Data("jpeg".utf8))
        let location = VideoLocation(name: "Tour Eiffel", address: "Paris, France")
        let upload = try create(
            file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "Avec @lea", userID: "a",
            extras: PublicationExtras(aiGenerated: true, location: location, cover: cover))
        #expect(upload.coverFileName == "u1-cover.jpg" && upload.coverSize == 4 && upload.aiGenerated && upload.location == location)

        let use = UploadVideoUseCase(videos: videos, stories: FakeStoryRepository(), transport: transport, store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.extras(of: "vid-1") == UploadExtras(aiGenerated: true, location: location, coverSize: 4))
        #expect(transport.received("http://storage.test/vid-1/cover") == Data("jpeg".utf8))
        #expect(transport.contentType("http://storage.test/vid-1/cover") == "image/jpeg")
        #expect(transport.calls.last?.absoluteString == "http://storage.test/vid-1/cover")
        #expect(store.fileNames.isEmpty)

        // Story : ni couverture, ni lieu, ni étiquette.
        let storyCover = store.addPickedFile("c.jpg", Data("jpeg".utf8))
        let story = try CreatePublicationUseCase(store: store, makeID: { "s1" })(
            file: store.addPickedFile("s.mov", Data("0123".utf8)), description: "", userID: "a", kind: .story,
            extras: PublicationExtras(aiGenerated: true, location: location, cover: storyCover))
        #expect(story.coverFileName == nil && story.location == nil && !story.aiGenerated)

        // Envoi enregistré avant l'ADR-065.
        let json = #"{"id":"u1","userID":"a","fileName":"f","contentType":"video/mp4","fileSize":1,"createdAt":0}"#
        let old = try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8))
        #expect(!old.aiGenerated && old.location == nil && old.coverFileName == nil && !old.coverSent)
    }

    @Test("envoi : couverture refusée par le stockage (URL expirée) → l'envoi repart de zéro et la renvoie")
    func coverRestart() async throws {
        let videos = FakeVideoPublishingRepository()
        let transport = FakePartTransport()
        let upload = try CreatePublicationUseCase(store: store, makeID: { "u2" })(
            file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "", userID: "a",
            extras: PublicationExtras(cover: store.addPickedFile("cover.jpg", Data("jpeg".utf8))))
        let failing = FailingOnCover(inner: transport)
        let use = UploadVideoUseCase(videos: videos, stories: FakeStoryRepository(), transport: failing, store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.created == ["vid-1", "vid-2"] && videos.deleted == ["vid-1"])
        #expect(transport.received("http://storage.test/vid-2/cover") == Data("jpeg".utf8))
    }

    // MARK: Brouillons

    @Test("brouillons sur disque : fichiers déplacés dans le brouillon, rendus à l'ouverture (qui le supprime), par compte")
    func draftStore() throws {
        let root = URL.temporaryDirectory.appending(path: "drafts-\(UUID().uuidString)", directoryHint: .isDirectory)
        let drafts = FileDraftStore(directory: root.appending(path: "Drafts"), temporaryDirectory: root.appending(path: "tmp"))
        let clip = try temporaryClip(4)
        let voiceFile = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data("voix".utf8).write(to: voiceFile)
        var plan = EditPlan(clips: [clip], kind: .video)
        plan.setVoiceovers([VoiceoverClip(id: UUID(), file: voiceFile, start: .seconds(1), duration: .seconds(1), offset: .milliseconds(200))])
        plan.filter = .mono
        let draft = VideoDraft(
            id: "d1", userID: "a", savedAt: Date(), plan: plan, source: .camera, description: "Ma vidéo #été", visibility: .onlyMe,
            commentsEnabled: false, soundShared: false, aiGenerated: true, location: VideoLocation(name: "Parc"),
            cover: CoverChoice(time: .seconds(2)))

        let saved = try drafts.save(draft, thumbnail: Data("jpeg".utf8))
        #expect(!exists(clip) && !FileManager.default.fileExists(atPath: voiceFile.path()))
        #expect(saved.plan.files.allSatisfy { $0.path().hasPrefix(root.path()) && FileManager.default.fileExists(atPath: $0.path()) })
        #expect(drafts.all(userID: "a") == [saved] && drafts.all(userID: "b").isEmpty)
        #expect(drafts.thumbnailURL(of: saved) != nil)
        // Le plan relu garde son montage.
        let read = try #require(drafts.all(userID: "a").first)
        #expect(read.plan.filter == .mono && read.plan.voiceovers.first?.offset == .milliseconds(200) && read.cover.time == .seconds(2))

        let opened = try drafts.open(saved)
        #expect(drafts.all(userID: "a").isEmpty)
        #expect(opened.plan.files.allSatisfy { FileManager.default.fileExists(atPath: $0.path()) && !$0.path().contains("/Drafts/") })
        #expect(opened.plan.clips.map(\.source.duration) == [.seconds(4)])

        var again = opened
        again.cover = CoverChoice()
        _ = try drafts.save(again, thumbnail: nil)
        drafts.deleteAll()
        #expect(drafts.all(userID: "a").isEmpty)
    }

    func makePublishing() async -> (PublishingModel, SessionStore) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let videos = FakeVideoPublishingRepository()
        let stories = FakeStoryRepository()
        let publishing = PublishingModel(
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
        return (publishing, session)
    }

    // Vidéo exportée connue du stockage des envois de test (fichier réel, pour les brouillons).
    func exportedFile() throws -> URL {
        let file = URL.temporaryDirectory.appending(path: "export-\(UUID().uuidString).mov")
        try Data("edited".utf8).write(to: file)
        store.state.withLock { $0.picked[file] = Data("edited".utf8) }
        return file
    }

    @Test("écran : mentions suggérées puis complétées ; enregistrer sur l'appareil refusé ; publication mesurée avec ses réglages")
    func postScreen() async throws {
        let (publishing, _) = await makePublishing()
        let search = FakeSearchRepository()
        let lea = UserSummary(id: "lea", username: "lea", displayName: "Léa", avatarURL: nil)
        search.state.withLock {
            $0.accounts["le"] = [AccountSearchPage(results: [AccountSearchResult(user: lea, followersCount: 1, viewer: nil)], nextCursor: nil)]
        }
        let preferences = InMemoryPublishingPreferences()
        let denied = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), preferences: preferences,
            suggestionDelay: .zero, makePreview: { _ in nil }, loadDuration: { _ in .seconds(8) },
            mentionSuggestions: MentionSuggestionsUseCase(relationships: FakeRelationshipRepository(), search: search),
            photoSaver: FakePhotoLibrarySaver(granted: false))

        denied.description = "Avec "
        denied.insertMentionSign()
        #expect(denied.description == "Avec @")
        denied.description += "le"
        await denied.waitForMentionSuggestions()
        #expect(denied.mentionSuggestions == [lea])
        denied.applyMention(lea)
        #expect(denied.description == "Avec @lea " && denied.mentionSuggestions.isEmpty)

        await denied.setSaveToDevice(true)
        #expect(!denied.saveToDevice && denied.errorMessage != nil && !preferences.saveToDevice)

        let saver = FakePhotoLibrarySaver(granted: true)
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), preferences: preferences,
            makePreview: { _ in nil }, loadDuration: { _ in .seconds(8) }, photoSaver: saver)
        await draft.setSaveToDevice(true)
        #expect(draft.saveToDevice && preferences.saveToDevice)

        let clip = try temporaryClip(8)
        let request = EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .gallery)
        await draft.edited(EditResult(file: try exportedFile(), plan: request.plan), request: request)
        draft.description = "Avec @lea et @nathan"
        draft.aiGenerated = true
        draft.location = VideoLocation(name: "Parc", address: "Paris")
        var cover = CoverChoice(time: .seconds(3))
        cover.style = .pill
        cover.setTitle("Été")
        draft.setCover(cover, image: UIImage(systemName: "star"))
        #expect(draft.coverImage != nil)
        #expect(draft.publish())
        let event = try #require(analytics.events.first { $0.name == "video_upload_started" })
        #expect(event.properties["cover_changed"] == .bool(true) && event.properties["cover_title"] == .bool(true))
        #expect(event.properties["location_added"] == .bool(true) && event.properties["mention_count"] == .int(2))
        #expect(event.properties["ai_generated"] == .bool(true) && event.properties["saved_to_device"] == .bool(true))
        let upload = try #require(store.uploads.first)
        #expect(upload.aiGenerated && upload.location?.name == "Parc")
        // Réglages remis à zéro pour la publication suivante.
        #expect(!draft.aiGenerated && draft.location == nil && !draft.cover.isCustom)
    }

    @Test("brouillon : enregistré depuis l'écran de publication (vidéo exportée supprimée), rouvert avec ses réglages")
    func saveAndRestoreDraft() async throws {
        let (publishing, session) = await makePublishing()
        let root = URL.temporaryDirectory.appending(path: "drafts-\(UUID().uuidString)", directoryHint: .isDirectory)
        let drafts = DraftsModel(
            store: FileDraftStore(directory: root.appending(path: "Drafts"), temporaryDirectory: root.appending(path: "tmp")), session: session)
        let draft = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), makePreview: { _ in nil },
            loadDuration: { _ in .seconds(5) }, drafts: drafts)
        let clip = try temporaryClip(5)
        var plan = EditPlan(clips: [clip], kind: .video)
        plan.filter = .warm
        let exported = try exportedFile()
        await draft.edited(EditResult(file: exported, plan: plan), request: EditorRequest(plan: plan, source: .camera))
        draft.description = "Plus tard"
        draft.visibility = .onlyMe
        draft.location = VideoLocation(name: "Parc")

        #expect(await draft.saveCurrentDraft())
        #expect(draft.state == .empty && draft.description.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: exported.path()) && !exists(clip))
        #expect(drafts.count == 1 && analytics.events.contains { $0.name == "draft_saved" })

        let opened = try drafts.open(try #require(drafts.drafts.first))
        #expect(drafts.count == 0)
        let next = PublishDraftViewModel(
            publishing: publishing, prepareVideo: PrepareVideoUseCase(cleaner: FakeVideoMetadataCleaner(store: store)), drafts: drafts)
        next.restore(opened)
        let request = try #require(next.editorRequest)
        #expect(request.plan.filter == .warm && request.source == .camera)
        #expect(next.description == "Plus tard" && next.visibility == .onlyMe && next.location?.name == "Parc")
        #expect(analytics.events.contains { $0.name == "draft_opened" })
    }

    @Test("lieux : recherche après la frappe ; lieux proches seulement une fois la localisation autorisée")
    func places() async {
        let search = FakePlaceSearch()
        let parc = VideoLocation(name: "Parc", address: "Paris")
        search.results["parc"] = [parc]
        search.nearbyPlaces = [VideoLocation(name: "Café")]
        let model = PlacePickerModel(places: search, searchDelay: .milliseconds(20))
        await model.loadNearby()
        #expect(model.access == .notDetermined && model.nearby.isEmpty)
        model.search("pa")
        model.search("parc")
        await model.waitForSearch()
        #expect(search.queries == ["parc"] && model.results == [parc])
        model.search("  ")
        #expect(model.results.isEmpty)
        await model.allowNearby()
        #expect(model.access == .authorized && model.nearby.map(\.name) == ["Café"])
    }
}

// Couverture refusée la première fois (URL expirée), le reste passe.
private final class FailingOnCover: UploadPartTransport {
    let inner: FakePartTransport
    private let refused = Mutex(false)

    init(inner: FakePartTransport) { self.inner = inner }

    func upload(_ data: Data, to url: URL, contentType: String?, sent: @escaping @Sendable (Int) -> Void) async throws -> String {
        if contentType != nil {
            let first = refused.withLock { value in
                defer { value = true }
                return !value
            }
            if first { throw UploadFailure.restartNeeded }
        }
        return try await inner.upload(data, to: url, contentType: contentType, sent: sent)
    }
}
