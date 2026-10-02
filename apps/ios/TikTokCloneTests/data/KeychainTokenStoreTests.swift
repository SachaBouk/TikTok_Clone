import Foundation
import Testing

@testable import TikTokClone

@Suite("KeychainTokenStore")
struct KeychainTokenStoreTests {
    // Service propre au test : n'efface pas la session de l'app.
    let store = KeychainTokenStore(service: "com.sachabouk.tiktokclone.tests.\(UUID().uuidString)")

    @Test("enregistre, remplace et efface la paire de tokens")
    func roundTrip() throws {
        #expect(store.load() == nil)
        let first = AuthTokens.valid("A1", refresh: "R1", now: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(first)
        #expect(store.load() == first)
        let second = AuthTokens.valid("A2", refresh: "R2")
        try store.save(second)
        #expect(store.load()?.accessToken == "A2")
        store.clear()
        #expect(store.load() == nil)
    }
}
