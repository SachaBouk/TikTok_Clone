import Foundation
import Synchronization
import Testing

@testable import TikTokClone

@Suite("Publication : envoi direct chez Mux (ADR-074)")
struct DirectUploadTests {
    let videos: FakeVideoPublishingRepository = {
        let videos = FakeVideoPublishingRepository()
        videos.state.withLock { $0.direct = true }
        return videos
    }()
    let transport = FakePartTransport()
    let store = InMemoryUploadStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let url = "https://mux.test/upload/vid-1"

    var upload: UploadVideoUseCase {
        UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: transport, store: store, now: { [now] in now }, retryDelays: [.zero, .zero])
    }

    // Fichier de 10 octets : morceaux de 4, 4 et 2 octets.
    func stored() throws -> PendingUpload {
        let file = store.addPickedFile("clip.mp4", Data("0123456789".utf8))
        return try CreatePublicationUseCase(store: store, now: { [now] in now }, makeID: { "u1" })(file: file, description: "", userID: "alice-id")
    }

    @Test("règles : en-tête Content-Range, octets reçus d'après Range")
    func rules() {
        #expect(UploadRules.contentRange(0..<4, total: 10) == "bytes 0-3/10")
        #expect(UploadRules.contentRange(8..<10, total: 10) == "bytes 8-9/10")
        #expect(UploadRules.receivedBytes(rangeHeader: "bytes=0-262143") == 262_144)
        #expect(UploadRules.receivedBytes(rangeHeader: nil) == 0)
        #expect(UploadRules.receivedBytes(rangeHeader: "bytes=5-9") == nil)
        #expect(UploadRules.receivedBytes(rangeHeader: "n'importe quoi") == nil)
    }

    @Test("morceaux successifs sur la même URL, puis confirmation sans parties ; l'envoi est oublié")
    func sendsChunks() async throws {
        let progress = Mutex<[Double]>([])
        let video = try await upload(try stored()) { value in progress.withLock { $0.append(value) } }

        #expect(video.status == .processing)
        #expect(transport.chunks == [0..<4, 4..<8, 8..<10])
        #expect(transport.directFile(url) == Data("0123456789".utf8))
        #expect(videos.completed("vid-1") == [])
        #expect(transport.statusQueries == 0)
        #expect(store.uploads.isEmpty)
        let values = progress.withLock { $0 }
        #expect(values.last == 1)
        #expect(values == values.sorted())
    }

    @Test("morceau gardé en partie (308 plus court) : l'envoi reprend à l'octet reçu")
    func partialChunk() async throws {
        transport.state.withLock { $0.keepAtMost = 2 }
        _ = try await upload(try stored()) { _ in }
        #expect(transport.chunks == [0..<4, 2..<6, 6..<10])
        #expect(transport.directFile(url) == Data("0123456789".utf8))
    }

    @Test("réponse sans Range : le morceau est tenu pour reçu")
    func unknownReceived() async throws {
        transport.state.withLock { $0.unknownReceived = true }
        _ = try await upload(try stored()) { _ in }
        #expect(transport.chunks == [0..<4, 4..<8, 8..<10])
    }

    @Test("coupure : Mux est interrogé, puis l'envoi reprend ; coupure prolongée : l'erreur remonte, l'état reste")
    func networkErrors() async throws {
        transport.fail([AppError.network])
        _ = try await upload(try stored()) { _ in }
        #expect(transport.chunks == [0..<4, 0..<4, 4..<8, 8..<10])
        #expect(transport.statusQueries == 1)

        let second = FakePartTransport()
        second.fail([AppError.network, AppError.network, AppError.network, AppError.network])
        let failing = UploadVideoUseCase(
            videos: videos, stories: FakeStoryRepository(), transport: second, store: store, now: { [now] in now }, retryDelays: [.zero, .zero])
        let file = store.addPickedFile("autre.mp4", Data("0123456789".utf8))
        let create = CreatePublicationUseCase(store: store, now: { [now] in now }, makeID: { "u2" })
        let pending = try create(file: file, description: "", userID: "alice-id")
        await #expect(throws: AppError.network) { try await failing(pending) { _ in } }
        #expect(store.uploads.first { $0.id == "u2" }?.ticket?.directUploadURL != nil)
    }

    @Test("reprise après relance : Mux dit ce qu'il a reçu, seul le reste part")
    func resumesFromMux() async throws {
        var pending = try stored()
        pending.ticket = UploadTicket(
            videoID: "vid-1", partSize: 4, parts: [], expiresAt: now.addingTimeInterval(3600), directUploadURL: URL(string: url))
        pending.directSentBytes = 4
        try store.save(pending)
        videos.state.withLock { $0.videos["vid-1"] = OwnVideo(id: "vid-1", description: nil, status: .uploading, thumbnailURL: nil, createdAt: now) }
        // Mux avait en fait reçu 8 octets (réponse du dernier morceau perdue).
        transport.state.withLock { $0.direct[URL(string: url)!] = Data("01234567".utf8) }

        _ = try await upload(pending) { _ in }
        #expect(transport.statusQueries == 1)
        #expect(transport.chunks == [8..<10])
        #expect(transport.directFile(url) == Data("0123456789".utf8))
    }

    @Test("envoi expiré chez Mux : il repart une fois de zéro sur une nouvelle vidéo")
    func restarts() async throws {
        transport.fail([UploadFailure.restartNeeded])
        let video = try await upload(try stored()) { _ in }
        #expect(video.id == "vid-2")
        #expect(videos.deleted == ["vid-1"])
        #expect(transport.directFile("https://mux.test/upload/vid-2") == Data("0123456789".utf8))
    }

    @Test("un envoi enregistré avant l'ADR-074 se relit sans octets envoyés chez Mux")
    func decodesOldUpload() throws {
        let json = #"{"id":"u","userID":"a","fileName":"f.mp4","contentType":"video/mp4","fileSize":3,"createdAt":0}"#
        let decoded = try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8))
        #expect(decoded.directSentBytes == 0)
        #expect(decoded.sentBytes == 0)
    }
}
