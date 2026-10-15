import Foundation
import Synchronization

@testable import TikTokClone

// Adaptateurs en mémoire des ports du domaine, pour tester cas d'usage et ViewModels (ADR-002).
final class FakeAuthRepository: AuthRepository {
    struct State {
        var loginError: AppError?
        var registerError: AppError?
        var hasSession = false
        var logins: [String] = []
        var registrations: [Registration] = []
        var logoutCount = 0
    }

    let state: Mutex<State>

    init(hasSession: Bool = false, loginError: AppError? = nil, registerError: AppError? = nil) {
        state = Mutex(State(loginError: loginError, registerError: registerError, hasSession: hasSession))
    }

    func login(identifier: String, password: String) async throws {
        try state.withLock {
            $0.logins.append(identifier)
            if let error = $0.loginError { throw error }
            $0.hasSession = true
        }
    }

    func register(_ registration: Registration) async throws {
        try state.withLock {
            $0.registrations.append(registration)
            if let error = $0.registerError { throw error }
            $0.hasSession = true
        }
    }

    func logout() async {
        state.withLock {
            $0.logoutCount += 1
            $0.hasSession = false
        }
    }

    func hasStoredSession() -> Bool { state.withLock { $0.hasSession } }
}

final class FakeProfileRepository: ProfileRepository {
    struct State {
        var others: [String: UserProfile] = [:]
        var updates: [ProfileChanges] = []
        var calls: [String] = []
        var error: AppError?
        var deleted = false
    }

    let result: Mutex<Result<UserProfile, AppError>>
    let state = Mutex(State())

    init(_ result: Result<UserProfile, AppError> = .success(.alice)) {
        self.result = Mutex(result)
    }

    var calls: [String] { state.withLock { $0.calls } }
    var updates: [ProfileChanges] { state.withLock { $0.updates } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }

    func myProfile() async throws -> UserProfile {
        try result.withLock { $0 }.get()
    }

    func profile(username: String) async throws -> UserProfile {
        try state.withLock {
            $0.calls.append("profile-\(username)")
            guard let profile = $0.others[username] else { throw AppError.notFound }
            return profile
        }
    }

    func updateMyProfile(_ changes: ProfileChanges) async throws -> UserProfile {
        let current = try result.withLock { $0 }.get()
        return try state.withLock {
            $0.updates.append(changes)
            if let error = $0.error { throw error }
            let updated = UserProfile(
                id: current.id, username: changes.username ?? current.username, displayName: changes.displayName ?? current.displayName,
                avatarURL: current.avatarURL, bio: changes.bio.map { $0.isEmpty ? nil : $0 } ?? current.bio,
                followersCount: current.followersCount, followingCount: current.followingCount, createdAt: current.createdAt
            )
            result.withLock { $0 = .success(updated) }
            return updated
        }
    }

    func createAvatarUpload(type: AvatarImageType, size: Int) async throws -> AvatarUpload {
        try state.withLock {
            $0.calls.append("avatarUpload-\(type.rawValue)-\(size)")
            if let error = $0.error { throw error }
            return AvatarUpload(id: "avatar-1", uploadURL: URL(string: "http://storage.test/avatars/a")!, expiresAt: .now)
        }
    }

    func setAvatar(id: String) async throws -> UserProfile {
        state.withLock { $0.calls.append("setAvatar-\(id)") }
        return try withAvatar(URL(string: "http://cdn.test/avatars/\(id)"))
    }

    func removeAvatar() async throws -> UserProfile {
        state.withLock { $0.calls.append("removeAvatar") }
        return try withAvatar(nil)
    }

    func deleteAccount() async throws {
        try state.withLock {
            $0.calls.append("deleteAccount")
            if let error = $0.error { throw error }
            $0.deleted = true
        }
    }

    private func withAvatar(_ url: URL?) throws -> UserProfile {
        let current = try result.withLock { $0 }.get()
        let updated = UserProfile(
            id: current.id, username: current.username, displayName: current.displayName, avatarURL: url, bio: current.bio,
            followersCount: current.followersCount, followingCount: current.followingCount, createdAt: current.createdAt)
        result.withLock { $0 = .success(updated) }
        return updated
    }
}

extension UserProfile {
    static let alice = UserProfile(
        id: "0192f3a0-0000-7000-8000-000000000001",
        username: "alice",
        displayName: "Alice",
        avatarURL: nil,
        bio: "Bonjour",
        followersCount: 3,
        followingCount: 1,
        createdAt: Date(timeIntervalSince1970: 1_767_268_800)
    )
}

@MainActor
func makeSession(auth: FakeAuthRepository = FakeAuthRepository(), profiles: FakeProfileRepository = FakeProfileRepository()) -> SessionStore {
    SessionStore(restoreSession: RestoreSessionUseCase(auth: auth, profiles: profiles), logout: LogoutUseCase(auth: auth))
}
