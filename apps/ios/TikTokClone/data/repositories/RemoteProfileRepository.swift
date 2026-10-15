import Foundation
import TikTokAPI

// Profils par l'API (module users). Codes traduits en erreurs du domaine.
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

    func profile(username: String) async throws -> UserProfile {
        switch try await mappingErrors({ try await client.getProfile(path: .init(username: username)) }) {
        case .ok(let ok): return UserProfile(try ok.body.json)
        case .notFound: throw AppError.notFound
        case .gone: throw AppError.profileSuspended
        case .undocumented: throw AppError.unexpected
        }
    }

    func updateMyProfile(_ changes: ProfileChanges) async throws -> UserProfile {
        let body = Components.Schemas.UpdateProfileRequest(username: changes.username, displayName: changes.displayName, bio: changes.bio)
        switch try await mappingErrors({ try await client.updateMyProfile(body: .json(body)) }) {
        case .ok(let ok): return UserProfile(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .conflict: throw AppError.rejected("Ce pseudo est déjà pris.")
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func createAvatarUpload(type: AvatarImageType, size: Int) async throws -> AvatarUpload {
        let body = Components.Schemas.CreateAvatarUploadRequest(contentType: .init(type), fileSize: size)
        switch try await mappingErrors({ try await client.createAvatarUpload(body: .json(body)) }) {
        case .created(let created):
            let dto = try created.body.json
            guard let url = URL(string: dto.uploadUrl) else { throw AppError.unexpected }
            return AvatarUpload(id: dto.avatarId, uploadURL: url, expiresAt: dto.expiresAt)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func setAvatar(id: String) async throws -> UserProfile {
        switch try await mappingErrors({ try await client.setMyAvatar(body: .json(.init(avatarId: id))) }) {
        case .ok(let ok): return UserProfile(try ok.body.json)
        // Fichier absent, ou pas une vraie image du type annoncé.
        case .badRequest: throw AppError.rejected("Cette image n’a pas pu être utilisée. Choisis-en une autre.")
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func removeAvatar() async throws -> UserProfile {
        switch try await mappingErrors({ try await client.removeMyAvatar() }) {
        case .ok(let ok): return UserProfile(try ok.body.json)
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteAccount() async throws {
        switch try await mappingErrors({ try await client.deleteMyAccount() }) {
        case .noContent: return
        // Déjà supprimé : le résultat voulu est atteint.
        case .notFound: return
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension Components.Schemas.CreateAvatarUploadRequest.ContentTypePayload {
    init(_ type: AvatarImageType) {
        switch type {
        case .jpeg: self = .imageJpeg
        case .png: self = .imagePng
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
            createdAt: dto.createdAt,
            likesCount: dto.likesCount
        )
    }
}

// Photo de profil envoyée directement au stockage (PUT signé). Content-Type et taille font partie de la
// signature : une autre valeur est refusée (403).
struct URLSessionAvatarUploader: AvatarUploadTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func upload(_ data: Data, type: AvatarImageType, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(type.rawValue, forHTTPHeaderField: "Content-Type")
        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: data)
        } catch {
            throw AppError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AppError.unexpected }
        switch http.statusCode {
        case 200..<300: return
        // URL expirée (15 min) ou envoi non conforme à la signature.
        case 403: throw AppError.rejected("L’envoi de la photo a été refusé. Réessaie.")
        default: throw AppError.unexpected
        }
    }
}
