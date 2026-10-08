import Foundation
import TikTokAPI

// Stories par l'API (module stories, ADR-051). Codes traduits en erreurs du domaine.
struct RemoteStoryRepository: StoryRepository, StoryPublishingRepository {
    let client: Client

    func tray() async throws -> [StoryTrayEntry] {
        switch try await mappingErrors({ try await client.getStoryTray() }) {
        case .ok(let ok): return try ok.body.json.items.map(StoryTrayEntry.init)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func stories(username: String) async throws -> [Story] {
        switch try await mappingErrors({ try await client.listUserStories(path: .init(username: username)) }) {
        case .ok(let ok):
            let body = try ok.body.json
            let author = UserSummary(body.user)
            return body.items.compactMap { Story($0, author: author) }
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func recordView(storyID: String) async throws {
        switch try await mappingErrors({ try await client.viewStory(path: .init(id: storyID)) }) {
        case .noContent: return
        case .notFound: throw AppError.notFound
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func setLiked(storyID: String, liked: Bool) async throws {
        if liked {
            switch try await mappingErrors({ try await client.likeStory(path: .init(id: storyID)) }) {
            case .noContent: return
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .notFound: throw AppError.notFound
            case .unauthorized: throw AppError.sessionExpired
            case .tooManyRequests(let error): throw AppError.tooManyActions(.storyLikes, retryAfter: max(1, error.headers.retryAfter ?? 60))
            case .undocumented: throw AppError.unexpected
            }
        } else {
            switch try await mappingErrors({ try await client.unlikeStory(path: .init(id: storyID)) }) {
            case .noContent: return
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .notFound: throw AppError.notFound
            case .unauthorized: throw AppError.sessionExpired
            case .undocumented: throw AppError.unexpected
            }
        }
    }

    func viewers(storyID: String, cursor: String?) async throws -> StoryViewersPage {
        switch try await mappingErrors({ try await client.listStoryViewers(path: .init(id: storyID), query: .init(cursor: cursor)) }) {
        case .ok(let ok):
            let body = try ok.body.json
            return StoryViewersPage(
                viewers: body.items.map { StoryViewer(user: UserSummary($0.user), viewedAt: $0.viewedAt, liked: $0.liked) },
                nextCursor: body.nextCursor,
                stats: StoryStats(viewers: body.viewersCount, likes: body.likesCount)
            )
        case .badRequest: throw AppError.unexpected
        case .notFound: throw AppError.notFound
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    // ─── Publication ─────────────────────────────────────────────────────────

    func createUpload(contentType: MediaContentType, fileSize: Int) async throws -> UploadTicket {
        let body = Components.Schemas.CreateStoryUploadRequest(contentType: .init(contentType), fileSize: fileSize)
        switch try await mappingErrors({ try await client.createStoryUpload(body: .json(body)) }) {
        case .created(let created): return try UploadTicket(created.body.json)
        case .tooManyRequests(let error): throw AppError.tooManyActions(.stories, retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func completeUpload(storyID: String, parts: [UploadedPart]) async throws -> OwnVideo {
        let body = Components.Schemas.CompleteUploadRequest(parts: parts.map { .init(partNumber: $0.number, etag: $0.etag) })
        switch try await mappingErrors({ try await client.completeStoryUpload(path: .init(id: storyID), body: .json(body)) }) {
        case .ok(let ok): return OwnVideo(try ok.body.json)
        // Parties refusées ou story supprimée entre-temps : l'envoi repart de zéro. Une photo refusée (format) aussi ;
        // un second refus est montré.
        case .badRequest, .notFound: throw UploadFailure.restartNeeded
        case .conflict: throw UploadFailure.alreadyConfirmed
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func story(id: String) async throws -> OwnVideo {
        switch try await mappingErrors({ try await client.getStory(path: .init(id: id)) }) {
        case .ok(let ok): return OwnVideo(try ok.body.json)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteStory(id: String) async throws {
        switch try await mappingErrors({ try await client.deleteStory(path: .init(id: id)) }) {
        case .noContent: return
        case .notFound: return
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension Components.Schemas.CreateStoryUploadRequest.ContentTypePayload {
    init(_ contentType: MediaContentType) {
        switch contentType {
        case .mp4: self = .videoMp4
        case .quickTime: self = .videoQuicktime
        case .jpeg: self = .imageJpeg
        }
    }
}

extension UploadTicket {
    init(_ dto: Components.Schemas.StoryUploadResponse) throws {
        let parts = try dto.parts.map { part in
            guard let url = URL(string: part.url) else { throw AppError.unexpected }
            return Part(number: part.partNumber, url: url)
        }
        self.init(videoID: dto.story.id, partSize: dto.partSize, parts: parts, expiresAt: dto.expiresAt)
    }
}

extension OwnVideo {
    // Une story suivie dans la liste des publications (pas de description).
    init(_ dto: Components.Schemas.StoryResponse) {
        self.init(
            id: dto.id,
            description: nil,
            status: VideoStatus(dto.status),
            thumbnailURL: dto.thumbnailUrl.flatMap(URL.init(string:)),
            createdAt: dto.createdAt
        )
    }
}

extension VideoStatus {
    init(_ dto: Components.Schemas.StoryStatus) {
        switch dto {
        case .uploading: self = .uploading
        case .processing: self = .processing
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}

extension StoryMediaType {
    init(_ dto: Components.Schemas.StoryMediaType) {
        switch dto {
        case .video: self = .video
        case .photo: self = .photo
        }
    }
}

extension Story {
    // Mapping explicite (ADR-002). Nil pour une story incomplète (URL invalide, pas publiée) : elle est sautée.
    init?(_ dto: Components.Schemas.StoryItemResponse, author: UserSummary) {
        guard let mediaURL = dto.mediaUrl.flatMap(URL.init(string:)), let thumbnailURL = dto.thumbnailUrl.flatMap(URL.init(string:)),
            let publishedAt = dto.publishedAt, let expiresAt = dto.expiresAt
        else { return nil }
        self.init(
            id: dto.id,
            author: author,
            mediaType: StoryMediaType(dto.mediaType),
            mediaURL: mediaURL,
            thumbnailURL: thumbnailURL,
            publishedAt: publishedAt,
            expiresAt: expiresAt,
            viewed: dto.viewer?.viewed ?? false,
            liked: dto.viewer?.liked ?? false,
            stats: dto.stats.map { StoryStats(viewers: $0.viewersCount, likes: $0.likesCount) }
        )
    }
}

extension StoryTrayEntry {
    init(_ dto: Components.Schemas.StoryTrayItemResponse) {
        self.init(user: UserSummary(dto.user), storiesCount: dto.storiesCount, latestAt: dto.latestAt, hasUnseen: dto.hasUnseen)
    }
}
