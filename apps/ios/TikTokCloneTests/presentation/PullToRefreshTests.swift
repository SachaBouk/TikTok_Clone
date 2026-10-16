import Foundation
import Testing

@testable import TikTokClone

// Tirer pour actualiser à deux points (Messages, Profil) : règles du geste.
@Suite("Tirer pour actualiser")
struct PullToRefreshTests {
    @Test("les points apparaissent avec la distance tirée, entiers au seuil")
    func progress() {
        #expect(PullToRefresh.progress(pull: 0) == 0)
        #expect(PullToRefresh.progress(pull: PullToRefresh.threshold / 2) == 0.5)
        #expect(PullToRefresh.progress(pull: PullToRefresh.threshold * 3) == 1)
        #expect(PullToRefresh.progress(pull: -20) == 0)
    }

    @Test("relâché au-delà du seuil seulement, et jamais pendant une actualisation")
    func trigger() {
        #expect(!PullToRefresh.shouldRefresh(pull: PullToRefresh.threshold - 1, isRefreshing: false))
        #expect(PullToRefresh.shouldRefresh(pull: PullToRefresh.threshold, isRefreshing: false))
        #expect(!PullToRefresh.shouldRefresh(pull: PullToRefresh.threshold * 2, isRefreshing: true))
    }

    @Test("points au milieu de l'espace libéré ; pendant l'actualisation, au milieu de la hauteur gardée")
    func position() {
        #expect(PullToRefresh.indicatorCenter(pull: 80, isRefreshing: false) == 40)
        #expect(PullToRefresh.indicatorCenter(pull: 0, isRefreshing: true) == PullToRefresh.refreshingHeight / 2)
        #expect(PullToRefresh.indicatorCenter(pull: 100, isRefreshing: true) == 50)
    }

    @Test("pendant le geste, un échange complet des points par seuil tiré")
    func phase() {
        #expect(PullToRefresh.phase(pull: 0) == 0)
        #expect(PullToRefresh.phase(pull: PullToRefresh.threshold) == 1)
        #expect(PullToRefresh.phase(pull: -10) == 0)
    }
}
