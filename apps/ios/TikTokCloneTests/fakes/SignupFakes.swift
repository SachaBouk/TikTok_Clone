import Foundation
import Synchronization

@testable import TikTokClone

// Inscription par étapes (ADR-055) simulée : disponibilités et catalogue choisis par le test, envois enregistrés.
final class FakeSignupRepository: SignupRepository {
    struct State {
        var availability: [String: UsernameAvailability] = [:]
        var availabilityError: AppError?
        var checked: [String] = []
        var catalog: [Interest] = FakeSignupRepository.defaultCatalog
        var catalogError: AppError?
        var mine: [String] = []
        var saveError: AppError?
        var saved: [[String]] = []
    }

    static let defaultCatalog = [
        Interest(code: "animals", name: "Animaux", emoji: "🐱"),
        Interest(code: "travel", name: "Voyage", emoji: "🏝️"),
        Interest(code: "food", name: "Cuisine", emoji: "🍔"),
        Interest(code: "music", name: "Musique", emoji: "🎵"),
    ]

    let state = Mutex(State())

    func usernameAvailability(_ username: String) async throws -> UsernameAvailability {
        try state.withLock {
            $0.checked.append(username)
            if let error = $0.availabilityError { throw error }
            return $0.availability[username] ?? .available
        }
    }

    func interestCatalog() async throws -> [Interest] {
        try state.withLock {
            if let error = $0.catalogError { throw error }
            return $0.catalog
        }
    }

    func myInterests() async throws -> [String] {
        state.withLock { $0.mine }
    }

    func setMyInterests(_ codes: [String]) async throws -> [String] {
        try state.withLock {
            if let error = $0.saveError { throw error }
            $0.saved.append(codes)
            $0.mine = codes
            return codes
        }
    }
}
