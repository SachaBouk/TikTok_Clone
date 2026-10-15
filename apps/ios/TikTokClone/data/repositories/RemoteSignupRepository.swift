import Foundation
import TikTokAPI

// Inscription par étapes (ADR-055) : disponibilité du pseudo et catalogue publics, centres d'intérêt du compte.
struct RemoteSignupRepository: SignupRepository {
    let client: Client

    func usernameAvailability(_ username: String) async throws -> UsernameAvailability {
        switch try await mappingErrors({ try await client.checkUsernameAvailability(query: .init(username: username)) }) {
        case .ok(let ok):
            let availability = try ok.body.json
            if availability.available { return .available }
            switch availability.reason {
            case .reserved: return .reserved
            case .taken: return .taken
            case .invalid, nil: return .invalid
            }
        case .undocumented: throw AppError.unexpected
        }
    }

    func interestCatalog() async throws -> [Interest] {
        switch try await mappingErrors({ try await client.getInterestCatalog() }) {
        case .ok(let ok): return try ok.body.json.items.map { Interest(code: $0.code, name: $0.name, emoji: $0.emoji) }
        case .undocumented: throw AppError.unexpected
        }
    }

    func myInterests() async throws -> [String] {
        switch try await mappingErrors({ try await client.getMyInterests() }) {
        case .ok(let ok): return try ok.body.json.interests
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func setMyInterests(_ codes: [String]) async throws -> [String] {
        switch try await mappingErrors({ try await client.setMyInterests(body: .json(.init(interests: codes))) }) {
        case .ok(let ok): return try ok.body.json.interests
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized, .notFound: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}
