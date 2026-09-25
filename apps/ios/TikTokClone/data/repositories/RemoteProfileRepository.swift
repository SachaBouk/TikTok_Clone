import Foundation
import TikTokAPI

struct RemoteProfileRepository: ProfileRepository {
    let client: Client

    func myProfile() async throws -> UserProfile {
        let output = try await mappingErrors { try await client.getMyProfile() }
        switch output {
        case .ok(let ok): return UserProfile(try ok.body.json)
        // 401 après échec du rafraîchissement, ou compte supprimé (404).
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension UserProfile {
    // Mapping explicite du DTO vers l'entité du domaine (ADR-002).
    init(_ dto: Components.Schemas.UserProfileResponse) {
        self.init(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName,
            avatarURL: dto.avatarUrl.flatMap(URL.init(string:)),
            bio: dto.bio,
            followersCount: dto.followersCount,
            followingCount: dto.followingCount,
            createdAt: dto.createdAt
        )
    }
}
