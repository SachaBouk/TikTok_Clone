import Foundation
import Synchronization
import Testing
import TikTokAPI

@testable import TikTokClone

// Lien de téléchargement de test (ADR-067) : renvoie un lien, ou l'erreur choisie.
final class FakeVideoDownloadRepository: VideoDownloadRepository {
    let error: AppError?
    let requested = Mutex<[String]>([])

    init(error: AppError? = nil) { self.error = error }

    func downloadLink(videoID: String) async throws -> VideoDownloadLink {
        requested.withLock { $0.append(videoID) }
        if let error { throw error }
        return VideoDownloadLink(url: URL(string: "https://minio.test/raw/\(videoID).mp4")!, fileName: "\(videoID).mp4", size: 4)
    }
}

// Téléchargement de test : écrit un petit fichier temporaire, avec une progression.
struct FakeFileDownloader: FileDownloader {
    func download(_ url: URL, fileName: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(0.5)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + fileName)
        try Data("0123".utf8).write(to: file)
        progress(1)
        return file
    }
}

@Suite("Menu d'une vidéo : vitesse")
struct PlaybackSpeedRulesTests {
    @Test("la vitesse du menu et le ×2 verrouillé sont un seul réglage")
    func speedAndLock() {
        var fast = FastPlayback()
        fast.setSpeed(.oneAndHalf)
        #expect(fast.rate == 1.5)
        #expect(!fast.isLocked)
        // Appui long : ×2 ; glisser vers le bas puis relâcher : 2.0×.
        fast.begin()
        #expect(fast.rate == 2)
        fast.drag(translation: 60)
        #expect(fast.end() == .locked)
        #expect(fast.speed == .double)
        // 2.0× choisi dans le menu : verrouillé ; l'appui lit à vitesse normale, le déverrouillage revient à 1.0×.
        fast.setSpeed(.double)
        fast.begin()
        #expect(fast.rate == 1)
        fast.drag(translation: 60)
        #expect(fast.end() == .unlocked)
        #expect(fast.speed == .normal)
    }

    @Test("libellés et vitesse suivante de l'affichage allégé")
    func labels() {
        #expect(PlaybackSpeed.allCases.map(\.label) == ["0.5×", "1.0×", "1.5×", "2.0×"])
        #expect(PlaybackSpeed.allCases.map(\.shortLabel) == ["0.5×", "1×", "1.5×", "2×"])
        #expect(PlaybackSpeed.normal.next == .oneAndHalf)
        #expect(PlaybackSpeed.double.next == .half)
    }
}

@MainActor
@Suite("Menu d'une vidéo")
struct VideoMenuTests {
    @Test("vitesse, défilement automatique et affichage allégé : appliqués, mesurés, oubliés à la déconnexion")
    func options() async throws {
        let playback = FakePlayback()
        let service = FakeAnalyticsService()
        let options = PlaybackOptionsModel(playback: playback, analytics: makeAnalytics(service), noticeDuration: .milliseconds(50))
        options.setSpeed(.half)
        options.setSpeed(.half)
        #expect(playback.rates == [0.5])
        #expect(service.eventNames == ["playback_speed_changed"])

        options.setAutoScroll(true)
        #expect(options.autoScroll)
        #expect(options.notice == .autoScrollOn)
        options.setAutoScroll(false)
        #expect(options.notice == .autoScrollOff)
        try await Task.sleep(for: .milliseconds(300))
        #expect(options.notice == nil)

        options.setClearMode(true)
        #expect(options.isClearMode)
        #expect(service.eventNames.suffix(3) == ["auto_scroll_changed", "auto_scroll_changed", "clear_mode_changed"])

        options.setAutoScroll(true)
        options.reset()
        #expect(!options.autoScroll)
        #expect(!options.isClearMode)
        #expect(options.speed == .normal)
        #expect(playback.rates.last == 1)
    }

    @Test("défilement automatique : à la fin de la vidéo courante lue, l'entrée suivante ; rien sinon")
    func autoScrollNextEntry() async throws {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let viewModel = FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: FakeFeedRepository([.success(page(["a", "b"], next: nil))])),
            recordView: RecordViewUseCase(history: FakeViewHistoryRepository()), playback: FakePlayback(), session: session,
            analytics: makeAnalytics(), mode: .followingFeed, viewDelay: .seconds(60))
        await viewModel.start()
        let entries = viewModel.entries.map(\.id)
        #expect(viewModel.entryAfterEnd(of: "b") == nil)
        #expect(viewModel.entryAfterEnd(of: "a") == entries[1])
        viewModel.togglePause()
        #expect(viewModel.entryAfterEnd(of: "a") == nil)
        viewModel.togglePause()
        viewModel.show(entries[1])
        // Dernière vidéo d'une liste qui s'arrête : pas de suivante.
        #expect(viewModel.entryAfterEnd(of: "b") == nil)
    }

    @Test("« Pas intéressé(e) » : la vidéo est retirée, mesurée, oubliée à la déconnexion")
    func notInterested() async {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let service = FakeAnalyticsService()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: FakeInteractionRepository()),
            setFollow: SetFollowUseCase(interactions: FakeInteractionRepository()),
            recordShare: ShareVideoUseCase(interactions: FakeInteractionRepository()),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()), session: session, analytics: makeAnalytics(service))
        interactions.notInterested(in: .sample("v1"))
        interactions.notInterested(in: .sample("v1"))
        #expect(interactions.notInterestedVideoIDs == ["v1"])
        #expect(service.eventNames == ["video_not_interested"])
        interactions.forgetReportedVideos()
        #expect(interactions.notInterestedVideoIDs.isEmpty)
    }

    @Test("télécharger : lien, fichier enregistré dans Photos, fichier temporaire supprimé")
    func download() async throws {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let photos = FakePhotoLibrarySaver(granted: true)
        let links = FakeVideoDownloadRepository()
        let service = FakeAnalyticsService()
        let model = VideoDownloadModel(
            download: DownloadVideoUseCase(links: links, files: FakeFileDownloader(), photos: photos), session: session,
            analytics: makeAnalytics(service), messageDuration: .milliseconds(30))
        await model.start(.sample("v1"))
        #expect(links.requested.withLock { $0 } == ["v1"])
        let saved = try #require(photos.saved.withLock { $0 }.first)
        #expect(saved.lastPathComponent.hasSuffix("v1.mp4"))
        #expect(!FileManager.default.fileExists(atPath: saved.path))
        #expect(service.eventNames == ["video_downloaded"])
        #expect(model.state == .idle)
    }

    @Test("télécharger : Photos refusé, refus de l'auteur, vidéo disparue ; invité : connexion")
    func downloadErrors() async throws {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        func run(_ links: FakeVideoDownloadRepository, granted: Bool = true) async -> VideoDownloadModel.State? {
            let model = VideoDownloadModel(
                download: DownloadVideoUseCase(links: links, files: FakeFileDownloader(), photos: FakePhotoLibrarySaver(granted: granted)),
                session: session, analytics: nil, messageDuration: .seconds(5))
            let task = Task { await model.start(.sample("v1")) }
            for _ in 0..<100 where !(model.state != .idle && !model.isDownloading) { try? await Task.sleep(for: .milliseconds(10)) }
            task.cancel()
            return model.state
        }
        #expect(await run(FakeVideoDownloadRepository(), granted: false) == .failed(DownloadVideoUseCase.photosDenied))
        let refused = "Le téléchargement de cette vidéo n’est pas autorisé."
        #expect(await run(FakeVideoDownloadRepository(error: .rejected(refused))) == .failed(refused))
        #expect(await run(FakeVideoDownloadRepository(error: .notFound)) == .failed("Cette vidéo n’est plus disponible."))

        let guest = makeSession(auth: FakeAuthRepository(hasSession: false))
        await guest.restore()
        let links = FakeVideoDownloadRepository()
        let model = VideoDownloadModel(
            download: DownloadVideoUseCase(links: links, files: FakeFileDownloader(), photos: FakePhotoLibrarySaver(granted: true)),
            session: guest, analytics: nil)
        await model.start(.sample("v1"))
        #expect(guest.isPresentingSignIn)
        #expect(links.requested.withLock { $0 }.isEmpty)
    }

    @Test("réglage de l'auteur : part avec l'envoi, changé depuis la feuille de partage ; envoi d'avant : autorisé")
    func downloadSetting() async throws {
        let videos = FakeVideoPublishingRepository()
        let store = InMemoryUploadStore()
        let create = CreatePublicationUseCase(store: store, makeID: { "u1" })
        let upload = try create(
            file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "", userID: "a",
            extras: PublicationExtras(downloadsEnabled: false))
        #expect(!upload.downloadsEnabled)
        let use = UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: FakePartTransport(), store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.extras(of: "vid-1")?.downloadsEnabled == false)
        let json = #"{"id":"u1","userID":"a","fileName":"f","contentType":"video/mp4","fileSize":1,"createdAt":0}"#
        #expect(try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8)).downloadsEnabled)

        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: FakeInteractionRepository()),
            setFollow: SetFollowUseCase(interactions: FakeInteractionRepository()),
            recordShare: ShareVideoUseCase(interactions: FakeInteractionRepository()),
            deleteVideo: DeleteVideoUseCase(videos: videos), setDownloadsEnabled: SetDownloadsEnabledUseCase(videos: videos),
            session: session, analytics: makeAnalytics())
        let mine = FeedVideo.sample("v1", author: "alice").byAlice
        #expect(await interactions.setDownloadsEnabled(false, of: mine) == nil)
        #expect(!interactions.display(mine).downloadsEnabled)
        #expect(videos.downloadsEnabled(of: "v1") == false)
        videos.state.withLock { $0.visibilityError = .network }
        #expect(await interactions.setDownloadsEnabled(true, of: mine) == AppError.network.message)
        #expect(!interactions.display(mine).downloadsEnabled)
        // Une vidéo aimée garde ses autres réglages (lieu, étiquette IA).
        var located = mine
        located.location = VideoLocation(name: "Annecy", address: nil)
        #expect(located.with(viewer: nil).location?.name == "Annecy")
    }

    @Test("API : lien de téléchargement, refus de l'auteur (403), limite (429)")
    func downloadLinkAPI() async throws {
        func repository(_ respond: @escaping @Sendable (String) -> (HTTPResponse, HTTPBody?)) -> RemoteInteractionRepository {
            RemoteInteractionRepository(client: makeClient(transport: MockTransport { _, operationID in respond(operationID) }))
        }
        let ok =
            #"{"url":"https://minio.test/raw/v1.mp4","expiresAt":"2026-11-03T10:15:00.000Z","contentType":"video/mp4","fileName":"v1.mp4","size":42}"#
        #expect(
            try await repository { _ in json(.ok, ok) }.downloadLink(videoID: "v1")
                == VideoDownloadLink(url: URL(string: "https://minio.test/raw/v1.mp4")!, fileName: "v1.mp4", size: 42))
        await #expect(throws: AppError.rejected("Refusé")) {
            try await repository { _ in json(.forbidden, errorJSON(403, "Refusé")) }.downloadLink(videoID: "v1")
        }
        await #expect(throws: AppError.tooManyActions(.downloads, retryAfter: 60)) {
            try await repository { _ in tooManyRequests(retryAfter: 60) }.downloadLink(videoID: "v1")
        }
        await #expect(throws: AppError.notFound) {
            try await repository { _ in json(.notFound, errorJSON(404, "Vidéo introuvable")) }.downloadLink(videoID: "v1")
        }
    }
}
