import Foundation
import Synchronization

@testable import TikTokClone

// API des vidéos en mémoire : parties de `partSize` octets, vidéos `vid-1`, `vid-2`…
final class FakeVideoPublishingRepository: VideoPublishingRepository {
    struct State {
        var partSize = 4
        var created: [String] = []
        var completed: [String: [UploadedPart]] = [:]
        var deleted: [String] = []
        var videos: [String: OwnVideo] = [:]
        var pending: [OwnVideo] = []
        // Erreurs à lever, dans l'ordre, par la prochaine confirmation.
        var completeErrors: [any Error] = []
        var createError: AppError?
        var expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        // Visibilité demandée à la création, puis changée (ADR-061), par vidéo.
        var visibilities: [String: VideoVisibility] = [:]
        var commentsEnabled: [String: Bool] = [:]
        // « Autoriser l'utilisation de mon son » et son repris, par vidéo créée (ADR-064).
        var sounds: [String: (shared: Bool, soundID: String?)] = [:]
        // Réglages de l'écran de publication (ADR-065), par vidéo créée.
        var extras: [String: UploadExtras] = [:]
        var visibilityError: AppError?
    }

    let state = Mutex(State())

    var created: [String] { state.withLock { $0.created } }
    var deleted: [String] { state.withLock { $0.deleted } }
    func completed(_ id: String) -> [UploadedPart]? { state.withLock { $0.completed[id] } }

    func visibility(of id: String) -> VideoVisibility? { state.withLock { $0.visibilities[id] } }
    func commentsEnabled(of id: String) -> Bool? { state.withLock { $0.commentsEnabled[id] } }
    func sound(of id: String) -> (shared: Bool, soundID: String?)? { state.withLock { $0.sounds[id] } }
    func extras(of id: String) -> UploadExtras? { state.withLock { $0.extras[id] } }

    func setCommentsEnabled(videoID: String, enabled: Bool) async throws {
        try state.withLock { state in
            if let error = state.visibilityError { throw error }
            state.commentsEnabled[videoID] = enabled
        }
    }

    func setVisibility(videoID: String, visibility: VideoVisibility) async throws {
        try state.withLock { state in
            if let error = state.visibilityError { throw error }
            state.visibilities[videoID] = visibility
        }
    }

    func createUpload(
        contentType: MediaContentType, fileSize: Int, description: String?, visibility: VideoVisibility, commentsEnabled: Bool,
        soundShared: Bool, soundID: String?, extras: UploadExtras
    ) async throws -> UploadTicket {
        try state.withLock { state in
            if let error = state.createError { throw error }
            let id = "vid-\(state.created.count + 1)"
            state.created.append(id)
            state.visibilities[id] = visibility
            state.commentsEnabled[id] = commentsEnabled
            state.sounds[id] = (soundShared, soundID)
            state.extras[id] = extras
            state.videos[id] = OwnVideo(id: id, description: description, status: .uploading, thumbnailURL: nil, createdAt: .now)
            let count = max(1, (fileSize + state.partSize - 1) / state.partSize)
            let parts = (1...count).map { UploadTicket.Part(number: $0, url: URL(string: "http://storage.test/\(id)/\($0)")!) }
            return UploadTicket(
                videoID: id, partSize: state.partSize, parts: parts, expiresAt: state.expiresAt,
                coverURL: extras.coverSize == nil ? nil : URL(string: "http://storage.test/\(id)/cover"))
        }
    }

    func completeUpload(videoID: String, parts: [UploadedPart]) async throws -> OwnVideo {
        try state.withLock { state in
            if !state.completeErrors.isEmpty { throw state.completeErrors.removeFirst() }
            state.completed[videoID] = parts
            let video = OwnVideo(
                id: videoID, description: state.videos[videoID]?.description, status: .processing, thumbnailURL: nil, createdAt: .now)
            state.videos[videoID] = video
            return video
        }
    }

    func video(id: String) async throws -> OwnVideo {
        try state.withLock { state in
            guard let video = state.videos[id] else { throw AppError.notFound }
            return video
        }
    }

    func pendingVideos() async throws -> [OwnVideo] {
        state.withLock { $0.pending }
    }

    func deleteVideo(id: String) async throws {
        state.withLock { state in
            state.deleted.append(id)
            state.videos[id] = nil
            state.pending.removeAll { $0.id == id }
        }
    }
}

// Stockage objet en mémoire : garde les parties reçues ; ETag = "etag-<URL>".
final class FakePartTransport: UploadPartTransport {
    struct State {
        var received: [URL: Data] = [:]
        var calls: [URL] = []
        // Erreurs à lever, dans l'ordre, par les prochains envois.
        var errors: [any Error] = []
        var delay: Duration = .zero
        // Type envoyé pour chaque URL (couverture, ADR-065).
        var contentTypes: [URL: String] = [:]
    }

    let state = Mutex(State())

    var calls: [URL] { state.withLock { $0.calls } }
    func received(_ url: String) -> Data? { state.withLock { $0.received[URL(string: url)!] } }
    func fail(_ errors: [any Error]) { state.withLock { $0.errors = errors } }

    func contentType(_ url: String) -> String? { state.withLock { $0.contentTypes[URL(string: url)!] } }

    func upload(_ data: Data, to url: URL, contentType: String?, sent: @escaping @Sendable (Int) -> Void) async throws -> String {
        let delay = state.withLock { $0.delay }
        if delay > .zero { try await Task.sleep(for: delay) }
        return try state.withLock { state in
            state.calls.append(url)
            if !state.errors.isEmpty { throw state.errors.removeFirst() }
            sent(data.count)
            state.received[url] = data
            if let contentType { state.contentTypes[url] = contentType }
            return "\"etag-\(url.absoluteString)\""
        }
    }
}

// Stockage local des envois en mémoire. Les fichiers « choisis » sont déclarés par `addPickedFile`.
final class InMemoryUploadStore: UploadStore {
    struct State {
        var uploads: [String: PendingUpload] = [:]
        var files: [String: Data] = [:]
        var picked: [URL: Data] = [:]
        var saves = 0
    }

    let state = Mutex(State())

    var uploads: [PendingUpload] { state.withLock { Array($0.uploads.values) } }
    var fileNames: [String] { state.withLock { Array($0.files.keys) } }
    var saves: Int { state.withLock { $0.saves } }

    func addPickedFile(_ name: String, _ data: Data) -> URL {
        let url = URL(filePath: "/tmp/Picked/\(name)")
        state.withLock { $0.picked[url] = data }
        return url
    }

    func all() -> [PendingUpload] { uploads }

    func save(_ upload: PendingUpload) throws {
        state.withLock {
            $0.uploads[upload.id] = upload
            $0.saves += 1
        }
    }

    func remove(_ upload: PendingUpload) {
        state.withLock {
            $0.uploads[upload.id] = nil
            $0.files[upload.fileName] = nil
            if let cover = upload.coverFileName { $0.files[cover] = nil }
        }
    }

    func size(ofFileAt url: URL) throws -> Int {
        try state.withLock {
            guard let data = $0.picked[url] else { throw AppError.unexpected }
            return data.count
        }
    }

    func adoptFile(at url: URL, id: String) throws -> String {
        try state.withLock {
            guard let data = $0.picked.removeValue(forKey: url) else { throw AppError.unexpected }
            let name = "\(id).\(url.pathExtension)"
            $0.files[name] = data
            return name
        }
    }

    func fileURL(named fileName: String) -> URL {
        URL(filePath: "/tmp/Uploads/\(fileName)")
    }

    func read(fileName: String, range: Range<Int>) throws -> Data {
        try state.withLock {
            guard let data = $0.files[fileName] else { throw AppError.rejected("fichier absent") }
            return data.subdata(in: range)
        }
    }
}

extension PendingUpload {
    static func sample(
        id: String = "u1", size: Int = 10, createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000), userID: String = UserProfile.alice.id
    ) -> PendingUpload {
        PendingUpload(
            id: id, userID: userID, fileName: "\(id).mov", contentType: .quickTime, fileSize: size, description: "Ma vidéo", createdAt: createdAt)
    }
}

// Attend qu'une condition devienne vraie (tâches de fond du modèle), 2 s au plus.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

// Nettoyage des métadonnées en mémoire, sur les fichiers « choisis » du magasin : le fichier est renommé
// (`…-clean.mov`), l'original disparaît, comme avec l'adaptateur AVFoundation. `fails` simule une vidéo qu'on ne
// sait pas ré-écrire (le fichier reçu disparaît aussi).
final class FakeVideoMetadataCleaner: VideoMetadataCleaner {
    let store: InMemoryUploadStore
    let fails: Bool
    private let calls = Mutex<[URL]>([])
    var cleaned: [URL] { calls.withLock { $0 } }

    init(store: InMemoryUploadStore, fails: Bool = false) {
        self.store = store
        self.fails = fails
    }

    func clean(_ file: URL) async throws -> URL {
        calls.withLock { $0.append(file) }
        let output = file.deletingPathExtension().appendingPathExtension("clean.mov")
        try store.state.withLock { state in
            guard let data = state.picked.removeValue(forKey: file) else { throw AppError.unexpected }
            if fails { throw CocoaError(.fileReadCorruptFile) }
            state.picked[output] = data
        }
        return output
    }
}

// Audience par défaut des publications (ADR-062), en mémoire.
final class InMemoryPublishingPreferences: PublishingPreferences {
    private let state = Mutex(VideoVisibility.everyone)
    private let saving = Mutex(false)

    var defaultVisibility: VideoVisibility { state.withLock { $0 } }
    func setDefaultVisibility(_ visibility: VideoVisibility) { state.withLock { $0 = visibility } }
    var saveToDevice: Bool { saving.withLock { $0 } }
    func setSaveToDevice(_ enabled: Bool) { saving.withLock { $0 = enabled } }
}
