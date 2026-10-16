import Foundation
import Testing

@testable import TikTokClone

// Toucher l'onglet Accueil déjà affiché : étapes de l'icône (maison → flèche qui tourne → maison).
@Suite("Onglet Accueil : icône du rechargement")
struct HomeTabIconTests {
    @Test("la maison rétrécit, puis la flèche grandit et tourne (un tour en 0,8 s)")
    func start() {
        #expect(HomeTabIcon.at(elapsed: 0, endedFor: nil) == .frame(symbol: "house.fill", angle: 0, scale: 1))
        #expect(HomeTabIcon.at(elapsed: 0.05, endedFor: nil) == .frame(symbol: "house.fill", angle: 0, scale: 0.5))
        guard case .frame(let symbol, let angle, let scale) = HomeTabIcon.at(elapsed: 0.5, endedFor: nil) else {
            Issue.record("étape attendue")
            return
        }
        #expect(symbol == "arrow.clockwise")
        #expect(abs(angle - 180) < 0.001)
        #expect(scale == 1)
    }

    @Test("à la fin, la flèche rétrécit, la maison grandit, puis l'icône de la barre revient")
    func end() {
        guard case .frame(let symbol, _, let scale) = HomeTabIcon.at(elapsed: 1, endedFor: 0.05) else {
            Issue.record("étape attendue")
            return
        }
        #expect(symbol == "arrow.clockwise")
        #expect(abs(scale - 0.5) < 0.001)
        guard case .frame(let returning, _, let growth) = HomeTabIcon.at(elapsed: 1.1, endedFor: 0.15) else {
            Issue.record("étape attendue")
            return
        }
        #expect(returning == "house.fill")
        #expect(abs(growth - 0.5) < 0.001)
        #expect(HomeTabIcon.at(elapsed: 1.2, endedFor: 0.2) == .standard)
    }

    @Test("la fin attend que la flèche se soit montrée")
    func canEnd() {
        #expect(!HomeTabIcon.canEnd(elapsed: 0.1))
        #expect(HomeTabIcon.canEnd(elapsed: 0.2))
    }
}
