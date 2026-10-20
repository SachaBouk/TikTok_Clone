import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

private let videoJSON = """
    {"id":"0192f3a0-0000-7000-8000-00000000000a","userId":"0192f3a0-0000-7000-8000-000000000001","description":"Ma vidéo",\
    "status":"processing","visibility":"public","commentsEnabled":true,"soundShared":true,"hlsUrl":null,"thumbnailUrl":null,"createdAt":"2026-09-25T12:00:00.123Z"}
    """

@Suite("RemoteVideoPublishingRepository")
struct RemoteVideoPublishingRepositoryTests {
    func repository(_ respond: @escaping @Sendable (String) -> (HTTPResponse, HTTPBody?)) -> RemoteVideoPublishingRepository {
        RemoteVideoPublishingRepository(client: makeClient(transport: MockTransport { _, operationID in respond(operationID) }))
    }

    @Test("createUpload : 429 (ADR-039) → trop d'envois, avec le délai de Retry-After")
    func createUploadRateLimited() async {
        await #expect(throws: AppError.tooManyActions(.uploads, retryAfter: 5400)) {
            try await repository { _ in tooManyRequests(retryAfter: 5400) }.createUpload(
                contentType: .mp4, fileSize: 1000, description: nil, visibility: .everyone, commentsEnabled: true)
        }
    }

    @Test("createUpload : une URL par partie, taille des parties, expiration")
    func createUpload() async throws {
        let body = """
            {"video":\(videoJSON),"partSize":10485760,"parts":[{"partNumber":1,"url":"http://localhost:9000/videos-raw/a?partNumber=1"},\
            {"partNumber":2,"url":"http://localhost:9000/videos-raw/a?partNumber=2"}],"expiresAt":"2026-09-25T14:00:00.000Z"}
            """
        let ticket = try await repository { _ in json(.created, body) }.createUpload(
            contentType: .quickTime, fileSize: 12_000_000, description: nil, visibility: .everyone, commentsEnabled: true)
        #expect(ticket.videoID == "0192f3a0-0000-7000-8000-00000000000a")
        #expect(ticket.partSize == 10_485_760)
        #expect(ticket.parts.map(\.number) == [1, 2])
        #expect(ticket.parts[1].url.absoluteString == "http://localhost:9000/videos-raw/a?partNumber=2")
    }

    @Test("createUpload refusé : message de l'API")
    func createRejected() async {
        await #expect(throws: AppError.rejected("fichier trop volumineux")) {
            try await repository { _ in json(.badRequest, errorJSON(400, "fichier trop volumineux")) }.createUpload(
                contentType: .mp4, fileSize: 1, description: nil, visibility: .everyone, commentsEnabled: true)
        }
    }

    @Test("commentaires coupés ou rétablis (ADR-062) : vidéo inconnue → introuvable")
    func setCommentsEnabled() async throws {
        try await repository { _ in json(.ok, videoJSON) }.setCommentsEnabled(videoID: "v", enabled: false)
        await #expect(throws: AppError.notFound) {
            try await repository { _ in json(.notFound, errorJSON(404, "Vidéo introuvable")) }.setCommentsEnabled(videoID: "v", enabled: true)
        }
    }

    @Test("completeUpload : 409 → déjà confirmé ; 400 et 404 → envoi à refaire")
    func completeErrors() async throws {
        let video = try await repository { _ in json(.ok, videoJSON) }.completeUpload(videoID: "v", parts: [UploadedPart(number: 1, etag: "\"e\"")])
        #expect(video.status == .processing)
        #expect(video.description == "Ma vidéo")
        await #expect(throws: UploadFailure.alreadyConfirmed) {
            try await repository { _ in json(.conflict, errorJSON(409, "x")) }.completeUpload(videoID: "v", parts: [])
        }
        await #expect(throws: UploadFailure.restartNeeded) {
            try await repository { _ in json(.badRequest, errorJSON(400, "x")) }.completeUpload(videoID: "v", parts: [])
        }
        await #expect(throws: UploadFailure.restartNeeded) {
            try await repository { _ in json(.notFound, errorJSON(404, "x")) }.completeUpload(videoID: "v", parts: [])
        }
    }

    @Test("vidéos en attente, suppression (déjà supprimée : sans erreur), session expirée")
    func pendingAndDelete() async throws {
        let pending = try await repository { _ in json(.ok, #"{"items":[\#(videoJSON)]}"#) }.pendingVideos()
        #expect(pending.map(\.status) == [.processing])
        try await repository { _ in (HTTPResponse(status: .notFound, headerFields: [.contentType: "application/json"]), HTTPBody(errorJSON(404, "x")))
        }.deleteVideo(id: "v")
        await #expect(throws: AppError.sessionExpired) {
            try await repository { _ in json(.unauthorized, errorJSON(401, "x")) }.pendingVideos()
        }
    }
}

@Suite("FileUploadStore")
struct FileUploadStoreTests {
    let directory = URL.temporaryDirectory.appending(path: "UploadStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test("fichier adopté, état enregistré et relu, lecture d'une partie, suppression")
    func roundTrip() throws {
        let store = FileUploadStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let picked = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).MOV")
        try Data("0123456789".utf8).write(to: picked)

        #expect(try store.size(ofFileAt: picked) == 10)
        let name = try store.adoptFile(at: picked, id: "u1")
        #expect(name == "u1.mov")
        #expect(!FileManager.default.fileExists(atPath: picked.path(percentEncoded: false)))

        let saved = PendingUpload(
            id: "u1", userID: "alice-id", fileName: name, contentType: .quickTime, fileSize: 10, description: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            ticket: UploadTicket(
                videoID: "v", partSize: 4, parts: [.init(number: 1, url: URL(string: "http://s.test/1")!)],
                expiresAt: Date(timeIntervalSince1970: 1_800_007_200)),
            sentParts: [1: "\"etag\""]
        )
        try store.save(saved)
        #expect(store.all() == [saved])
        #expect(try store.read(fileName: name, range: 4..<8) == Data("4567".utf8))
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        store.remove(saved)
        #expect(store.all().isEmpty)
        #expect(throws: AppError.self) { try store.read(fileName: name, range: 0..<1) }
    }
}

@Suite("Temps réel : décodage, adresse, reconnexion")
struct RealtimeDataTests {
    @Test("videoProcessed décodé en vidéo du domaine ; événements inconnus et messages illisibles ignorés")
    func decode() {
        let decoder = RealtimeEventDecoder()
        let ready = videoJSON.replacingOccurrences(of: #""status":"processing""#, with: #""status":"ready""#)
            .replacingOccurrences(of: #""thumbnailUrl":null"#, with: #""thumbnailUrl":"http://cdn.test/a/thumbnail.jpg""#)
        let update = decoder.decode(#"{"event":"videoProcessed","data":\#(ready)}"#)
        guard case .videoProcessed(let video)? = update else {
            Issue.record("videoProcessed attendu, reçu \(String(describing: update))")
            return
        }
        #expect(video.status == .ready)
        #expect(video.thumbnailURL?.absoluteString == "http://cdn.test/a/thumbnail.jpg")
        #expect(decoder.decode(#"{"event":"inconnu","data":{}}"#) == nil)
        #expect(decoder.decode("pas du json") == nil)
    }

    @Test("adresse du WebSocket : même hôte que l'API, ws ou wss")
    func realtimeURL() {
        #expect(AppConfiguration(apiBaseURL: URL(string: "http://localhost:3000")!).realtimeURL.absoluteString == "ws://localhost:3000/realtime")
        #expect(AppConfiguration(apiBaseURL: URL(string: "https://api.example.com/")!).realtimeURL.absoluteString == "wss://api.example.com/realtime")
    }

    @Test("délai de reconnexion : 1, 2, 4… 30 s, à ±20 % près")
    func reconnectPolicy() {
        let policy = ReconnectPolicy()
        #expect(policy.delay(attempt: 1, jitter: 0) == .seconds(1))
        #expect(policy.delay(attempt: 3, jitter: 0) == .seconds(4))
        #expect(policy.delay(attempt: 10, jitter: 0) == .seconds(30))
        #expect(policy.delay(attempt: 100, jitter: 0) == .seconds(30))
        #expect(policy.delay(attempt: 1, jitter: 1) == .milliseconds(1200))
        #expect(policy.delay(attempt: 1, jitter: -1) == .milliseconds(800))
    }
}
