import Foundation
import TikTokAPI

// Vidéos du compte connecté par l'API (module videos). Codes traduits en erreurs du domaine.
struct RemoteVideoPublishingRepository: VideoPublishingRepository {
    let client: Client

    func createUpload(contentType: MediaContentType, fileSize: Int, description: String?, visibility: VideoVisibility) async throws -> UploadTicket {
        // Une photo n'est publiée qu'en story (ADR-051).
        guard let type = Components.Schemas.CreateUploadRequest.ContentTypePayload(contentType) else {
            throw AppError.rejected("Format non pris en charge : choisis une vidéo MP4 ou MOV.")
        }
        let body = Components.Schemas.CreateUploadRequest(
            contentType: type, fileSize: fileSize, description: description, visibility: Components.Schemas.VideoVisibility(visibility))
        switch try await mappingErrors({ try await client.createUpload(body: .json(body)) }) {
        case .created(let created): return try UploadTicket(created.body.json)
        case .tooManyRequests(let error): throw AppError.tooManyActions(.uploads, retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func completeUpload(videoID: String, parts: [UploadedPart]) async throws -> OwnVideo {
        let body = Components.Schemas.CompleteUploadRequest(parts: parts.map { .init(partNumber: $0.number, etag: $0.etag) })
        switch try await mappingErrors({ try await client.completeUpload(path: .init(id: videoID), body: .json(body)) }) {
        case .ok(let ok): return OwnVideo(try ok.body.json)
        // Parties refusées (ETag, taille) ou vidéo supprimée entre-temps (upload abandonné depuis plus de 24 h).
        case .badRequest, .notFound: throw UploadFailure.restartNeeded
        case .conflict: throw UploadFailure.alreadyConfirmed
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func setVisibility(videoID: String, visibility: VideoVisibility) async throws {
        let body = Components.Schemas.SetVideoVisibilityRequest(visibility: .init(visibility))
        switch try await mappingErrors({ try await client.setVideoVisibility(path: .init(id: videoID), body: .json(body)) }) {
        case .ok: return
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func video(id: String) async throws -> OwnVideo {
        switch try await mappingErrors({ try await client.getVideo(path: .init(id: id)) }) {
        case .ok(let ok): return OwnVideo(try ok.body.json)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func pendingVideos() async throws -> [OwnVideo] {
        switch try await mappingErrors({ try await client.listMyPendingVideos() }) {
        case .ok(let ok): return try ok.body.json.items.map(OwnVideo.init)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteVideo(id: String) async throws {
        switch try await mappingErrors({ try await client.deleteVideo(path: .init(id: id)) }) {
        case .noContent: return
        // Déjà supprimée : le résultat voulu est atteint.
        case .notFound: return
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension Components.Schemas.CreateUploadRequest.ContentTypePayload {
    init?(_ contentType: MediaContentType) {
        switch contentType {
        case .mp4: self = .videoMp4
        case .quickTime: self = .videoQuicktime
        case .jpeg: return nil
        }
    }
}

extension UploadTicket {
    // Mapping explicite (ADR-002). Une URL de partie invalide rend l'envoi impossible.
    init(_ dto: Components.Schemas.VideoUploadResponse) throws {
        let parts = try dto.parts.map { part in
            guard let url = URL(string: part.url) else { throw AppError.unexpected }
            return Part(number: part.partNumber, url: url)
        }
        self.init(videoID: dto.video.id, partSize: dto.partSize, parts: parts, expiresAt: dto.expiresAt)
    }
}

extension OwnVideo {
    init(_ dto: Components.Schemas.VideoResponse) {
        self.init(
            id: dto.id,
            description: dto.description,
            status: VideoStatus(dto.status),
            thumbnailURL: dto.thumbnailUrl.flatMap(URL.init(string:)),
            createdAt: dto.createdAt
        )
    }
}

extension VideoStatus {
    init(_ dto: Components.Schemas.VideoStatus) {
        switch dto {
        case .uploading: self = .uploading
        case .processing: self = .processing
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}

extension Components.Schemas.VideoVisibility {
    init(_ visibility: VideoVisibility) {
        switch visibility {
        case .everyone: self = ._public
        case .onlyMe: self = ._private
        }
    }
}

extension VideoVisibility {
    init(_ dto: Components.Schemas.VideoVisibility) {
        switch dto {
        case ._public: self = .everyone
        case ._private: self = .onlyMe
        }
    }
}
