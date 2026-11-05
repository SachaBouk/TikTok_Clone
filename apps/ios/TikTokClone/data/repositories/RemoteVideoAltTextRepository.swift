import Foundation
import TikTokAPI

// Texte alternatif d'une vidéo par l'API (module videos, ADR-076).
struct RemoteVideoAltTextRepository: VideoAltTextRepository {
    let client: Client

    func setAltText(videoID: String, altText: String?) async throws {
        let body = Components.Schemas.SetAltTextRequest(altText: altText)
        switch try await mappingErrors({ try await client.setVideoAltText(path: .init(id: videoID), body: .json(body)) }) {
        case .ok: return
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }
}
