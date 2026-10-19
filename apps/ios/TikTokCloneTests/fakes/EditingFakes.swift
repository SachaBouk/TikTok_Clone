import CoreGraphics
import Foundation
import Synchronization

@testable import TikTokClone

// Caméra simulée (ADR-052) : le test décide du démarrage, termine lui-même les segments et rend une photo.
@MainActor
final class FakeVideoCamera: VideoCamera {
    var startResult: CameraStart = .ready(hasAudio: true)
    var hasTorch = true
    var switchSucceeds = true
    var photo: Result<Data, any Error> = .success(Data("photo".utf8))
    private(set) var started: [CameraPosition] = []
    private(set) var stopCount = 0
    private(set) var torch: [Bool] = []
    // Durée maximale demandée pour chaque segment.
    private(set) var recordings: [Duration] = []
    private(set) var stopRecordingCount = 0
    private var onFinish: (@MainActor (Result<SourceClip, any Error>) -> Void)?

    var isRecording: Bool { onFinish != nil }

    func start(position: CameraPosition) async -> CameraStart {
        started.append(position)
        return startResult
    }

    func stop() { stopCount += 1 }

    func switchTo(_ position: CameraPosition) async -> Bool { switchSucceeds }

    func setTorch(_ on: Bool) { torch.append(on) }

    func startRecording(maxDuration: Duration, onFinish: @escaping @MainActor (Result<SourceClip, any Error>) -> Void) {
        recordings.append(maxDuration)
        self.onFinish = onFinish
    }

    func stopRecording() { stopRecordingCount += 1 }

    // Fin du segment en cours (arrêt ou durée maximale atteinte).
    func finishSegment(_ result: Result<SourceClip, any Error>) {
        let finish = onFinish
        onFinish = nil
        finish?(result)
    }

    func capturePhoto() async throws -> Data { try photo.get() }
}

// Export simulé : chaque plan rend un fichier de la galerie simulée (`InMemoryUploadStore`), adoptable par la file d'envoi.
final class FakeVideoEditor: VideoEditor {
    let store: InMemoryUploadStore
    let fails: Bool
    private let calls = Mutex<[EditPlan]>([])
    var exported: [EditPlan] { calls.withLock { $0 } }

    init(store: InMemoryUploadStore, fails: Bool = false) {
        self.store = store
        self.fails = fails
    }

    func export(_ plan: EditPlan) async throws -> URL {
        let count = calls.withLock {
            $0.append(plan)
            return $0.count
        }
        if fails { throw CocoaError(.fileWriteUnknown) }
        return store.addPickedFile("edited-\(count).mov", Data("edited".utf8))
    }
}

// Vrai fichier temporaire (pour vérifier sa suppression), d'une durée annoncée.
func temporaryClip(_ seconds: Double) throws -> SourceClip {
    let directory = URL.temporaryDirectory.appending(path: "clips-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "segment.mov")
    try Data("segment".utf8).write(to: file)
    return SourceClip(file: file, duration: .milliseconds(Int64(seconds * 1000)))
}

func exists(_ clip: SourceClip) -> Bool {
    FileManager.default.fileExists(atPath: clip.file.path(percentEncoded: false))
}

// Galerie simulée (ADR-062) : autorisation, médias par album, miniatures et exports comptés.
final class FakeMediaLibrary: MediaLibrary, @unchecked Sendable {
    var accessState: MediaLibraryAccess = .notDetermined
    var grantedAccess: MediaLibraryAccess = .full
    var items: [LibraryAsset] = []
    var albumItems: [String: [LibraryAsset]] = [:]
    var albumList: [LibraryAlbum] = []
    private(set) var requests = 0
    private(set) var thumbnailRequests: [String] = []

    func access() -> MediaLibraryAccess { accessState }

    func requestAccess() async -> MediaLibraryAccess {
        requests += 1
        accessState = grantedAccess
        return accessState
    }

    func albums() async -> [LibraryAlbum] { albumList }

    func assets(in album: LibraryAlbum?, filter: LibraryFilter) async -> [LibraryAsset] {
        let source = album.map { albumItems[$0.id] ?? [] } ?? items
        switch filter {
        case .all: return source
        case .videos: return source.filter(\.isVideo)
        case .photos: return source.filter { !$0.isVideo }
        }
    }

    func thumbnail(of asset: LibraryAsset, side: Double) async -> CGImage? {
        thumbnailRequests.append(asset.id)
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }

    func exportVideo(_ asset: LibraryAsset) async throws -> URL { URL(filePath: "/tmp/\(asset.id).mov") }

    func photoData(_ asset: LibraryAsset) async throws -> Data { Data(asset.id.utf8) }
}
