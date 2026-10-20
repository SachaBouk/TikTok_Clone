import Foundation
import Synchronization
import Testing
import UIKit

@testable import TikTokClone

// Faux dépôt des sons (ADR-064) : sons par onglet, favoris, téléchargement dans un fichier temporaire.
final class FakeSoundRepository: SoundRepository, Sendable {
    struct State {
        var all: [Sound] = []
        var favoriteIDs: [String] = []
        var favoriteError: AppError?
        var searches: [String] = []
        var downloads: [String] = []
    }

    let state = Mutex(State())

    func recommended(cursor: String?) async throws -> SoundPage {
        SoundPage(items: state.withLock { $0.all }, nextCursor: nil)
    }

    func favorites(cursor: String?) async throws -> SoundPage {
        state.withLock { state in
            SoundPage(items: state.all.filter { state.favoriteIDs.contains($0.id) }, nextCursor: nil)
        }
    }

    func search(_ text: String, cursor: String?) async throws -> SoundPage {
        state.withLock { state in
            state.searches.append(text)
            return SoundPage(items: state.all.filter { $0.author.username.contains(text.lowercased()) }, nextCursor: nil)
        }
    }

    func sounds(ids: [String]) async throws -> [Sound] {
        state.withLock { state in ids.compactMap { id in state.all.first { $0.id == id } } }
    }

    func setFavorite(_ favorite: Bool, soundID: String) async throws {
        try state.withLock { state in
            if let error = state.favoriteError { throw error }
            state.favoriteIDs.removeAll { $0 == soundID }
            if favorite { state.favoriteIDs.append(soundID) }
        }
    }

    func download(_ sound: Sound) async throws -> URL {
        state.withLock { $0.downloads.append(sound.id) }
        return URL.temporaryDirectory.appending(path: "\(sound.id).m4a")
    }

    static func sound(_ id: String, by username: String, duration: Double = 20) -> Sound {
        Sound(
            id: id, videoID: "video-\(id)", author: UserSummary(id: username, username: username, displayName: username.capitalized, avatarURL: nil),
            audioURL: URL(string: "https://cdn/\(id)/sound.m4a")!, duration: .seconds(duration), coverURL: URL(string: "https://cdn/\(id).jpg")!,
            usesCount: 0, favorited: false)
    }
}

final class InMemoryRecentSoundsStore: RecentSoundsStore, Sendable {
    private let ids = Mutex<[String]>([])

    var recentSounds: [String] { ids.withLock { $0 } }
    func setRecentSounds(_ ids: [String]) { self.ids.withLock { $0 = ids } }
}

// Micro de test : un « enregistrement » de la durée choisie.
@MainActor
final class FakeVoiceRecorder: VoiceRecorder {
    var permission = true
    var recordedDuration: Duration = .seconds(1)
    private(set) var isRecording = false

    func requestPermission() async -> Bool { permission }

    func start() -> Bool {
        isRecording = true
        return true
    }

    func stop() -> (file: URL, duration: Duration)? {
        guard isRecording else { return nil }
        isRecording = false
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: file.path(), contents: Data("voix".utf8))
        return (file, recordedDuration)
    }
}

@MainActor
@Suite("Voix off, effets de voix et sons repris (ADR-064)")
struct SoundTests {
    @Test("bibliothèque : recommandés, recherche après la frappe, favori optimiste (retour en cas d'échec), choix retenu dans « Récents »")
    func library() async throws {
        let repository = FakeSoundRepository()
        repository.state.withLock { $0.all = [FakeSoundRepository.sound("s1", by: "lea"), FakeSoundRepository.sound("s2", by: "nathan")] }
        let store = InMemoryRecentSoundsStore()
        let library = SoundLibraryModel(repository: repository, store: store)
        library.reload()
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.items.map(\.id) == ["s1", "s2"])

        library.isSearching = true
        library.search("na")
        library.search("nath")
        try await Task.sleep(for: .milliseconds(500))
        #expect(repository.state.withLock { $0.searches } == ["nath"])
        #expect(library.items.map(\.id) == ["s2"])
        library.closeSearch()
        try await Task.sleep(for: .milliseconds(50))

        let lea = library.items[0]
        await library.toggleFavorite(lea)
        #expect(library.items[0].favorited)
        repository.state.withLock { $0.favoriteError = .network }
        await library.toggleFavorite(library.items[0])
        #expect(library.items[0].favorited && library.errorMessage == AppError.network.message)

        let chosen = try #require(await library.choose(lea))
        #expect(chosen.id == "s1" && chosen.start == .zero)
        _ = await library.choose(library.items[1])
        #expect(store.recentSounds == ["s2", "s1"])
        library.select(.recent)
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.items.map(\.id) == ["s2", "s1"])
        library.reset()
        #expect(store.recentSounds.isEmpty && library.items.isEmpty)
    }

    @Test("voix off : enregistrée à la tête de lecture, vidéo sans son pendant l'enregistrement ; sur une voix : refusée ; micro refusé")
    func voiceoverSession() async throws {
        let recorder = FakeVoiceRecorder()
        var time: Duration = .seconds(2)
        var playback: [(Bool, Bool)] = []
        let session = VoiceoverSession(
            clips: [], duration: .seconds(10), originalSound: true, recorder: recorder, currentTime: { time },
            playback: { playing, muted in playback.append((playing, muted)) })
        await session.startRecording()
        #expect(session.isRecording && playback.last! == (true, true))
        recorder.recordedDuration = .seconds(1.5)
        session.stopRecording()
        #expect(!session.isRecording && playback.last! == (false, false))
        #expect(session.clips.map(\.start) == [.seconds(2)] && session.clips[0].duration == .seconds(1.5))

        time = .seconds(3)
        await session.startRecording()
        #expect(!session.isRecording && session.errorMessage != nil)

        // Fichier plus long que la lecture : la voix finit à la tête de lecture, d'où l'on peut enregistrer la suite.
        session.errorMessage = nil
        time = .seconds(4)
        await session.startRecording()
        recorder.recordedDuration = .milliseconds(1_300)
        time = .seconds(5)
        session.stopRecording()
        #expect(session.clips.last?.duration == .seconds(1) && session.clips.last?.offset == .milliseconds(300))
        await session.startRecording()
        #expect(session.isRecording && session.errorMessage == nil)
        time = .seconds(5.5)
        session.stopRecording()
        session.removeLast()
        session.removeLast()

        session.errorMessage = nil
        recorder.permission = false
        time = .seconds(6)
        await session.startRecording()
        #expect(!session.isRecording && session.errorMessage?.contains("micro") == true)

        let file = session.clips[0].file
        session.removeLast()
        #expect(session.clips.isEmpty && !FileManager.default.fileExists(atPath: file.path()))
    }

    @Test("éditeur : voix off en un pas d'annulation, son repris qui coupe le son d'origine, volumes en un geste ; aperçu relu")
    func editor() async throws {
        let clip = try temporaryClip(8)
        let model = VideoEditorViewModel(
            request: EditorRequest(plan: EditPlan(clips: [clip], kind: .video), source: .camera),
            exportVideo: ExportEditedVideoUseCase(editor: FakeVideoEditor(store: InMemoryUploadStore())), makeThumbnails: { _, _ in [] })
        let voice = VoiceoverClip(id: UUID(), file: URL(filePath: "/tmp/v.m4a"), start: .seconds(1), duration: .seconds(2))
        model.setVoiceovers([voice], originalSound: false)
        #expect(model.plan.voiceovers == [voice] && model.plan.isMuted && model.previewVersion == 1)
        model.setVoiceEffect(.church)
        #expect(model.previewVersion == 2)
        model.undo()
        model.undo()
        #expect(model.plan.voiceovers.isEmpty && !model.plan.isMuted)

        let sound = ChosenSound(sound: FakeSoundRepository.sound("s1", by: "lea"), file: URL(filePath: "/tmp/s1.m4a"))
        model.setSound(sound)
        #expect(model.plan.sound?.id == "s1" && model.plan.isMuted)
        model.setSoundStart(.seconds(5))
        #expect(model.plan.sound?.start == .seconds(5))
        let version = model.previewVersion
        model.setAddedVolume(0.7)
        model.setAddedVolume(0.4)
        model.endInteraction()
        #expect(model.plan.addedVolume == 0.4 && model.previewVersion == version + 1)
        model.undo()
        #expect(model.plan.addedVolume == 1)
    }

    @Test("publication : son repris et « Autoriser l'utilisation de mon son » partent avec l'envoi ; une story partage toujours")
    func publication() async throws {
        let videos = FakeVideoPublishingRepository()
        let store = InMemoryUploadStore()
        let create = CreatePublicationUseCase(store: store, makeID: { "u1" })
        let upload = try create(
            file: store.addPickedFile("clip.mov", Data("0123".utf8)), description: "", userID: "a", soundShared: false, soundID: "s1")
        #expect(!upload.soundShared && upload.soundID == "s1")
        let story = try create(
            file: store.addPickedFile("s.mov", Data("0123".utf8)), description: "", userID: "a", kind: .story, soundShared: false, soundID: "s1")
        #expect(story.soundShared && story.soundID == nil)

        let use = UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: FakePartTransport(), store: store, retryDelays: [.zero])
        _ = try await use(upload) { _ in }
        #expect(videos.sound(of: "vid-1")?.shared == false && videos.sound(of: "vid-1")?.soundID == "s1")

        let json = #"{"id":"u1","userID":"a","fileName":"f","contentType":"video/mp4","fileSize":1,"createdAt":0}"#
        let old = try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8))
        #expect(old.soundShared && old.soundID == nil)
    }
}
