import Foundation
import Synchronization
import Testing

@testable import TikTokClone

@Suite("Publication : règles et envoi par parties")
struct PublishingUseCasesTests {
    let videos = FakeVideoPublishingRepository()
    let stories = FakeStoryRepository()
    let transport = FakePartTransport()
    let store = InMemoryUploadStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var upload: UploadVideoUseCase {
        UploadVideoUseCase(videos: videos, stories: stories, transport: transport, store: store, now: { [now] in now }, retryDelays: [.zero, .zero])
    }

    // Fichier de 10 octets enregistré pour l'envoi : 3 parties de 4, 4 et 2 octets.
    func stored(_ bytes: String = "0123456789") throws -> PendingUpload {
        let file = store.addPickedFile("clip.MOV", Data(bytes.utf8))
        return try CreatePublicationUseCase(store: store, now: { [now] in now }, makeID: { "u1" })(
            file: file, description: "  Ma vidéo \n", userID: "alice-id")
    }

    @Test("règles : parties, formats, description")
    func rules() {
        #expect(UploadRules.range(ofPart: 1, partSize: 4, fileSize: 10) == 0..<4)
        #expect(UploadRules.range(ofPart: 3, partSize: 4, fileSize: 10) == 8..<10)
        #expect(MediaContentType(fileExtension: "MOV") == .quickTime)
        #expect(MediaContentType(fileExtension: "m4v") == .mp4)
        #expect(MediaContentType(fileExtension: "avi") == nil)
        #expect(UploadRules.sanitizedDescription("  \n ") == nil)
        #expect(UploadRules.sanitizedDescription(" Salut ") == "Salut")
    }

    @Test("création : fichier adopté, description nettoyée, état enregistré")
    func create() throws {
        let pending = try stored()
        #expect(pending.fileName == "u1.MOV")
        #expect(pending.contentType == .quickTime)
        #expect(pending.fileSize == 10)
        #expect(pending.description == "Ma vidéo")
        #expect(pending.ticket == nil)
        #expect(store.uploads == [pending])
    }

    @Test("création refusée : format, description trop longue, fichier vide")
    func createRejected() {
        let create = CreatePublicationUseCase(store: store)
        #expect(throws: AppError.self) {
            try create(file: store.addPickedFile("clip.avi", Data("x".utf8)), description: "", userID: "a")
        }
        #expect(throws: AppError.rejected("La description fait au plus 2200 caractères.")) {
            try create(file: store.addPickedFile("clip.mp4", Data("x".utf8)), description: String(repeating: "a", count: 2201), userID: "a")
        }
        #expect(throws: AppError.rejected("Cette vidéo est vide.")) {
            try create(file: store.addPickedFile("vide.mp4", Data()), description: "", userID: "a")
        }
        #expect(store.uploads.isEmpty)
    }

    @Test("envoi : chaque partie une fois, dans l'ordre, puis confirmation avec les ETags ; l'envoi est oublié")
    func uploadAllParts() async throws {
        let progress = Mutex<[Double]>([])
        let video = try await upload(try stored()) { value in progress.withLock { $0.append(value) } }

        #expect(video.id == "vid-1")
        #expect(video.status == .processing)
        #expect(transport.received("http://storage.test/vid-1/1") == Data("0123".utf8))
        #expect(transport.received("http://storage.test/vid-1/3") == Data("89".utf8))
        #expect(videos.completed("vid-1") == (1...3).map { UploadedPart(number: $0, etag: "\"etag-http://storage.test/vid-1/\($0)\"") })
        #expect(store.uploads.isEmpty)
        #expect(store.fileNames.isEmpty)
        let values = progress.withLock { $0 }
        #expect(values.last == 1)
        #expect(values == values.sorted())
    }

    @Test("coupure prolongée : l'erreur remonte, les parties reçues sont enregistrées ; la reprise ne les renvoie pas")
    func resumeAfterNetworkFailure() async throws {
        let pending = try stored()
        // Partie 1 reçue, puis 3 échecs réseau sur la partie 2 (essai + 2 relances).
        transport.state.withLock { $0.errors = [] }
        let failing = UploadVideoUseCase(
            videos: videos, stories: stories, transport: FailingAfter(transport, successes: 1), store: store, retryDelays: [.zero, .zero])
        await #expect(throws: AppError.network) { try await failing(pending) { _ in } }

        let saved = try #require(store.uploads.first)
        #expect(saved.sentParts.keys.sorted() == [1])
        #expect(saved.ticket?.videoID == "vid-1")

        _ = try await upload(saved) { _ in }
        #expect(transport.calls.map(\.lastPathComponent) == ["1", "2", "3"])
        #expect(videos.created == ["vid-1"])
        #expect(videos.completed("vid-1")?.count == 3)
    }

    @Test("coupure brève : la partie est réessayée")
    func retriesPart() async throws {
        transport.fail([AppError.network, AppError.network])
        _ = try await upload(try stored()) { _ in }
        #expect(transport.calls.map(\.lastPathComponent) == ["1", "1", "1", "2", "3"])
    }

    @Test("URL refusée par le stockage : nouvel envoi complet sur une nouvelle vidéo, l'ancienne est supprimée")
    func restartsOnRejectedURL() async throws {
        transport.fail([UploadFailure.restartNeeded])
        let video = try await upload(try stored()) { _ in }
        #expect(video.id == "vid-2")
        #expect(videos.created == ["vid-1", "vid-2"])
        #expect(videos.deleted == ["vid-1"])
    }

    @Test("URLs expirées avant la reprise : nouvel envoi sans rien renvoyer sur les anciennes URLs")
    func restartsWhenTicketExpired() async throws {
        videos.state.withLock { $0.expiresAt = Date(timeIntervalSince1970: 1_800_000_030) }
        var pending = try stored()
        pending.ticket = try await videos.createUpload(
            contentType: .quickTime, fileSize: 10, description: nil, visibility: .everyone, commentsEnabled: true)
        pending.sentParts = [1: "\"a\""]
        let video = try await upload(pending) { _ in }
        #expect(video.id == "vid-2")
        #expect(videos.deleted == ["vid-1"])
        #expect(transport.calls.allSatisfy { $0.absoluteString.contains("vid-2") })
    }

    @Test("un second refus arrête l'envoi avec un message")
    func restartsOnce() async throws {
        transport.fail([UploadFailure.restartNeeded, UploadFailure.restartNeeded])
        await #expect(throws: AppError.rejected("Le serveur a refusé l’envoi. Réessaie.")) {
            try await upload(try stored()) { _ in }
        }
    }

    @Test("confirmation déjà faite (réponse perdue) : la vidéo est relue")
    func alreadyConfirmed() async throws {
        videos.state.withLock { $0.completeErrors = [UploadFailure.alreadyConfirmed] }
        let video = try await upload(try stored()) { _ in }
        #expect(video.id == "vid-1")
        #expect(store.uploads.isEmpty)
    }

    @Test("envois enregistrés : ceux du compte, les plus récents d'abord ; ceux de plus de 24 h sont oubliés")
    func pendingUploads() throws {
        try store.save(.sample(id: "old", createdAt: now.addingTimeInterval(-25 * 3600)))
        try store.save(.sample(id: "a", createdAt: now.addingTimeInterval(-60)))
        try store.save(.sample(id: "b", createdAt: now))
        try store.save(.sample(id: "other", createdAt: now, userID: "bob-id"))
        let result = PendingUploadsUseCase(store: store, now: { [now] in now })(userID: UserProfile.alice.id)
        #expect(result.map(\.id) == ["b", "a"])
        #expect(Set(store.uploads.map(\.id)) == ["a", "b", "other"])
    }

    @Test("abandon : vidéo supprimée côté API, envoi et fichier oubliés")
    func cancel() async throws {
        var pending = try stored()
        pending.ticket = try await videos.createUpload(
            contentType: .quickTime, fileSize: 10, description: nil, visibility: .everyone, commentsEnabled: true)
        await CancelUploadUseCase(videos: videos, stories: stories, store: store)(pending)
        #expect(videos.deleted == ["vid-1"])
        #expect(store.uploads.isEmpty)
        #expect(store.fileNames.isEmpty)
    }
}

// Réussit `successes` envois, puis échoue toujours (réseau).
private final class FailingAfter: UploadPartTransport {
    let inner: FakePartTransport
    let remaining: Mutex<Int>

    init(_ inner: FakePartTransport, successes: Int) {
        self.inner = inner
        remaining = Mutex(successes)
    }

    func upload(_ data: Data, to url: URL, sent: @escaping @Sendable (Int) -> Void) async throws -> String {
        let allowed = remaining.withLock { value in
            defer { value -= 1 }
            return value > 0
        }
        guard allowed else { throw AppError.network }
        return try await inner.upload(data, to: url, sent: sent)
    }
}
