import Foundation
import TikTokAPI

// Sons repris des vidéos (ADR-064) : routes du compte connecté ; fichiers téléchargés dans le dossier temporaire.
struct RemoteSoundRepository: SoundRepository {
    static let pageSize = 20

    let client: Client
    var session: URLSession = .shared

    func recommended(cursor: String?) async throws -> SoundPage {
        switch try await mappingErrors({ try await client.listRecommendedSounds(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
        case .ok(let ok): return try SoundPage(ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func favorites(cursor: String?) async throws -> SoundPage {
        switch try await mappingErrors({ try await client.listFavoriteSounds(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
        case .ok(let ok): return try SoundPage(ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func search(_ text: String, cursor: String?) async throws -> SoundPage {
        switch try await mappingErrors({ try await client.searchSounds(query: .init(cursor: cursor, limit: Self.pageSize, q: text)) }) {
        case .ok(let ok): return try SoundPage(ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func sounds(ids: [String]) async throws -> [Sound] {
        guard !ids.isEmpty else { return [] }
        switch try await mappingErrors({ try await client.getSounds(query: .init(ids: ids)) }) {
        case .ok(let ok): return try ok.body.json.items.compactMap(Sound.init)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func setFavorite(_ favorite: Bool, soundID: String) async throws {
        if favorite {
            switch try await mappingErrors({ try await client.favoriteSound(path: .init(id: soundID)) }) {
            case .noContent: return
            case .notFound: throw AppError.notFound
            case .unauthorized: throw AppError.sessionExpired
            case .undocumented: throw AppError.unexpected
            }
        } else {
            switch try await mappingErrors({ try await client.unfavoriteSound(path: .init(id: soundID)) }) {
            case .noContent: return
            case .unauthorized: throw AppError.sessionExpired
            case .undocumented: throw AppError.unexpected
            }
        }
    }

    func download(_ sound: Sound) async throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(sound.id).m4a")
        if FileManager.default.fileExists(atPath: file.path()) { return file }
        let (downloaded, response) = try await session.download(from: sound.audioURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: downloaded)
            throw AppError.notFound
        }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: downloaded, to: file)
        return file
    }
}

extension SoundPage {
    init(_ dto: Components.Schemas.SoundPageResponse) throws {
        self.init(items: dto.items.compactMap(Sound.init), nextCursor: dto.nextCursor)
    }
}

extension Sound {
    // Mapping explicite du DTO (ADR-002) ; nil si une URL est illisible.
    init?(_ dto: Components.Schemas.SoundResponse) {
        guard let audioURL = URL(string: dto.audioUrl), let coverURL = URL(string: dto.coverUrl) else { return nil }
        self.init(
            id: dto.id, videoID: dto.videoId, author: UserSummary(dto.author), audioURL: audioURL, duration: .seconds(dto.duration),
            coverURL: coverURL, usesCount: dto.usesCount, favorited: dto.viewer?.favorited ?? false)
    }
}
