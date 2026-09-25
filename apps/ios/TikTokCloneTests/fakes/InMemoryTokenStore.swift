import Foundation
import Synchronization
@testable import TikTokClone

// Adaptateur en mémoire du TokenStore (le Keychain a ses propres tests).
final class InMemoryTokenStore: TokenStore {
    private let tokens: Mutex<AuthTokens?>

    init(_ tokens: AuthTokens? = nil) {
        self.tokens = Mutex(tokens)
    }

    func load() -> AuthTokens? { tokens.withLock { $0 } }
    func save(_ tokens: AuthTokens) throws { self.tokens.withLock { $0 = tokens } }
    func clear() { tokens.withLock { $0 = nil } }
}

extension AuthTokens {
    static func valid(_ access: String = "A1", refresh: String = "R1", now: Date = Date()) -> AuthTokens {
        AuthTokens(accessToken: access, refreshToken: refresh, accessTokenExpiresAt: now.addingTimeInterval(900))
    }

    static func expired(_ access: String = "A1", refresh: String = "R1", now: Date = Date()) -> AuthTokens {
        AuthTokens(accessToken: access, refreshToken: refresh, accessTokenExpiresAt: now.addingTimeInterval(-60))
    }
}
