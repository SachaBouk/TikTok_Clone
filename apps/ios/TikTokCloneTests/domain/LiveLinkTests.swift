import Foundation
import Testing

@testable import TikTokClone

// Lien d'app d'un live du Live commun (ADR-079).
struct LiveLinkTests {
    @Test("identifiant du serveur commun, et UUID des anciens lives")
    func parsesLiveIDs() throws {
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://lives/live_8Kx-2"))) == "live_8Kx-2")
        let uuid = "0193b2c4-1111-7000-8000-000000000001"
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://lives/\(uuid)"))) == uuid)
        #expect(LiveLink.liveID(from: LiveLink.url(for: "abc")) == "abc")
    }

    @Test("refuse un autre hôte, un chemin en plusieurs parties ou des caractères interdits")
    func rejectsOthers() throws {
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://videos/abc"))) == nil)
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://lives/a/b"))) == nil)
        #expect(LiveLink.liveID(from: try #require(URL(string: "tiktokclone://lives/a%20b"))) == nil)
        #expect(LiveLink.liveID(from: try #require(URL(string: "https://lives/abc"))) == nil)
    }
}
