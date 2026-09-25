import Foundation
import Synchronization
@testable import TikTokClone

// Adaptateurs en mémoire des ports du domaine, pour tester cas d'usage et ViewModels (ADR-002).
final class FakeAuthRepository: AuthRepository {
    struct State {
        var loginError: AuthError?
        var registerError: AuthError?
        var hasSession = false
        var logins: [String] = []
        var registrations: [Registration] = []
        var logoutCount = 0
    }

    let state: Mutex<State>

    init(hasSession: Bool = false, loginError: AuthError? = nil, registerError: AuthError? = nil) {
        state = Mutex(State(loginError: loginError, registerError: registerError, hasSession: hasSession))
    }

    func login(email: String, password: String) async throws {
        try state.withLock {
            $0.logins.append(email)
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
    let result: Mutex<Result<UserProfile, AuthError>>

    init(_ result: Result<UserProfile, AuthError> = .success(.alice)) {
        self.result = Mutex(result)
    }

    func myProfile() async throws -> UserProfile {
        try result.withLock { $0 }.get()
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
