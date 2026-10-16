import Foundation
import Testing

@testable import TikTokClone

// Toucher un onglet de feed déjà affiché (Accueil, Amis) : étapes de l'icône (maison → flèche qui tourne → maison).
@Suite("Onglets de feed : icône du rechargement")
struct TabRefreshIconTests {
    @Test("la maison rétrécit, puis la flèche grandit et tourne (un tour en 0,8 s)")
    func start() {
        #expect(TabRefreshIcon.at(elapsed: 0, endedFor: nil, symbol: "house.fill") == .frame(symbol: "house.fill", angle: 0, scale: 1))
        #expect(TabRefreshIcon.at(elapsed: 0.05, endedFor: nil, symbol: "house.fill") == .frame(symbol: "house.fill", angle: 0, scale: 0.5))
        guard case .frame(let symbol, let angle, let scale) = TabRefreshIcon.at(elapsed: 0.5, endedFor: nil, symbol: "house.fill") else {
            Issue.record("étape attendue")
            return
        }
        #expect(symbol == "arrow.clockwise")
        #expect(abs(angle - 180) < 0.001)
        #expect(scale == 1)
    }

    @Test("à la fin, la flèche rétrécit, la maison grandit, puis l'icône de la barre revient")
    func end() {
        guard case .frame(let symbol, _, let scale) = TabRefreshIcon.at(elapsed: 1, endedFor: 0.05, symbol: "house.fill") else {
            Issue.record("étape attendue")
            return
        }
        #expect(symbol == "arrow.clockwise")
        #expect(abs(scale - 0.5) < 0.001)
        guard case .frame(let returning, _, let growth) = TabRefreshIcon.at(elapsed: 1.1, endedFor: 0.15, symbol: "house.fill") else {
            Issue.record("étape attendue")
            return
        }
        #expect(returning == "house.fill")
        #expect(abs(growth - 0.5) < 0.001)
        #expect(TabRefreshIcon.at(elapsed: 1.2, endedFor: 0.2, symbol: "house.fill") == .standard)
    }

    @Test("l'icône de l'onglet Amis rétrécit de la même façon")
    func friends() {
        #expect(TabRefreshIcon.at(elapsed: 0.05, endedFor: nil, symbol: "person.2.fill") == .frame(symbol: "person.2.fill", angle: 0, scale: 0.5))
    }

    @Test("la fin attend que la flèche se soit montrée")
    func canEnd() {
        #expect(!TabRefreshIcon.canEnd(elapsed: 0.1))
        #expect(TabRefreshIcon.canEnd(elapsed: 0.2))
    }
}
