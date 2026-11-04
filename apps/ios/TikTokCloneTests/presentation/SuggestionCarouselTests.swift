import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Carrousel de comptes suggérés")
struct SuggestionCarouselTests {
    let playback = FakePlayback()

    private func ids(_ count: Int, from start: Int = 1) -> [String] { (start..<(start + count)).map { "v\($0)" } }

    private func makeViewModel(_ pages: [Result<FeedPage, AppError>], mode: FeedViewModel.Mode = .endlessFeed) async -> FeedViewModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        return FeedViewModel(
            loadPage: LoadFeedPageUseCase(feed: FakeFeedRepository(pages)), recordView: RecordViewUseCase(history: FakeViewHistoryRepository()),
            playback: playback, session: session, analytics: makeAnalytics(), mode: mode, viewDelay: .milliseconds(20))
    }

    private func suggestion(followsYou: Bool = false, followedBy: [String] = [], count: Int = 0) -> AccountSuggestion {
        let users = followedBy.map { UserSummary(id: "\($0)-id", username: $0, displayName: $0.capitalized, avatarURL: nil) }
        return AccountSuggestion(
            user: UserSummary(id: "rm-id", username: "rm_91", displayName: "Rm_91", avatarURL: nil), followersCount: 10,
            followsYou: followsYou, followedBy: users, followedByCount: count)
    }

    @Test("emplacements : après la 8e vidéo, puis toutes les 30")
    func slots() {
        #expect(!SuggestionCarouselRules.isSlot(afterVideo: 7))
        #expect(SuggestionCarouselRules.isSlot(afterVideo: 8))
        #expect(!SuggestionCarouselRules.isSlot(afterVideo: 9))
        #expect(!SuggestionCarouselRules.isSlot(afterVideo: 30))
        #expect(SuggestionCarouselRules.isSlot(afterVideo: 38))
        #expect(SuggestionCarouselRules.isSlot(afterVideo: 68))
    }

    @Test("carte voisine après un ×, carte suivante après un abonnement")
    func neighbors() {
        #expect(SuggestionCarouselRules.neighbor(of: "b", in: ["a", "b", "c"]) == "c")
        #expect(SuggestionCarouselRules.neighbor(of: "c", in: ["a", "b", "c"]) == "b")
        #expect(SuggestionCarouselRules.neighbor(of: "a", in: ["a"]) == nil)
        #expect(SuggestionCarouselRules.next(after: "b", in: ["a", "b", "c"]) == "c")
        #expect(SuggestionCarouselRules.next(after: "c", in: ["a", "b", "c"]) == nil)
    }

    @Test("raison sous le nom, comme TikTok")
    func reasons() {
        #expect(suggestion().carouselReason == "Personnes que tu pourrais connaître")
        #expect(suggestion(followsYou: true, followedBy: ["hyaa8"], count: 1).carouselReason == "Fait partie de tes followers")
        #expect(suggestion(followedBy: ["hyaa8"], count: 1).carouselReason == "hyaa8 fait partie de ses followers")
        #expect(suggestion(followedBy: ["mny8", "lea"], count: 2).carouselReason == "Suivi(e) par mny8 et lea")
        #expect(
            suggestion(followedBy: ["mny8", "mny8881", "zoe"], count: 3).carouselReason
                == "Suivi(e) par mny8, mny8881 et 1 autre utilisateur(trice)")
        #expect(
            suggestion(followedBy: ["mny8", "mny8881", "zoe"], count: 7).carouselReason
                == "Suivi(e) par mny8, mny8881 et 5 autres utilisateur(trice)s")
    }

    @Test("couleur du fond : ravivée, luminosité moyenne ; grise pour une photo grise ; stable sans photo")
    func tones() {
        let blue = SuggestionTone(red: 0.05, green: 0.25, blue: 0.9)
        #expect(abs(blue.hue - 0.627) < 0.01)
        #expect(blue.brightness == SuggestionTone.maxBrightness)
        #expect(blue.saturation > 0.9)
        let dark = SuggestionTone(red: 0.2, green: 0.1, blue: 0.05)
        #expect(dark.brightness == SuggestionTone.minBrightness)
        #expect(dark.saturation >= 0.55)
        let gray = SuggestionTone(red: 0.5, green: 0.51, blue: 0.5)
        #expect(gray.saturation == 0)
        #expect(SuggestionTone.fallback(for: "rm_91") == SuggestionTone.fallback(for: "rm_91"))
    }

    @Test("le carrousel suit la 8e vidéo, seulement quand des suggestions sont à voir")
    func pages() async {
        let viewModel = await makeViewModel([.success(page(ids(10), next: "c1"))])
        await viewModel.start()
        #expect(viewModel.pages.count == 10)
        viewModel.setShowsSuggestions(true)
        #expect(viewModel.pages.count == 11)
        guard case .suggestions = viewModel.pages[8] else {
            Issue.record("carrousel attendu après la 8e vidéo")
            return
        }
        if case .video(let entry) = viewModel.pages[7] { #expect(entry.video.id == "v8") }
    }

    @Test("feed des abonnements : jamais de carrousel")
    func followingFeed() async {
        let viewModel = await makeViewModel([.success(page(ids(10), next: nil))], mode: .followingFeed)
        await viewModel.start()
        viewModel.setShowsSuggestions(true)
        #expect(viewModel.pages.count == 10)
    }

    @Test("carrousel affiché : aucune vidéo ne joue, la suivante reste préchargée ; défilement automatique jusqu'à lui")
    func showCarousel() async {
        let viewModel = await makeViewModel([.success(page(ids(12), next: "c1"))])
        await viewModel.start()
        viewModel.setShowsSuggestions(true)
        viewModel.show(viewModel.pages[7].id)
        #expect(viewModel.entryAfterEnd(of: "v8") == viewModel.pages[8].id)
        let pauses = playback.pauseCount
        let played = playback.played.count
        viewModel.show(viewModel.pages[8].id)
        #expect(viewModel.isShowingSuggestions)
        #expect(viewModel.currentVideo == nil)
        #expect(playback.pauseCount == pauses + 1)
        #expect(playback.played.count == played)
        #expect(playback.loaded.last?.contains("v9") == true)
        viewModel.show(viewModel.pages[9].id)
        #expect(viewModel.currentVideo?.id == "v9")
        #expect(playback.played.last == "v9")
    }

    @Test("toutes les suggestions écartées pendant l'affichage : la vidéo suivante devient courante")
    func carouselEmptied() async {
        let viewModel = await makeViewModel([.success(page(ids(12), next: "c1"))])
        await viewModel.start()
        viewModel.setShowsSuggestions(true)
        viewModel.show(viewModel.pages[8].id)
        viewModel.setShowsSuggestions(false)
        #expect(viewModel.pages.count == 12)
        #expect(viewModel.currentVideo?.id == "v9")
        #expect(playback.played.last == "v9")
    }

    @Test("vidéo d'ancrage retirée : le carrousel passe à la vidéo d'avant, toujours affiché")
    func anchorRemoved() async {
        let viewModel = await makeViewModel([.success(page(ids(12), next: "c1"))])
        await viewModel.start()
        viewModel.setShowsSuggestions(true)
        viewModel.show(viewModel.pages[8].id)
        viewModel.remove(videoIDs: ["v8"])
        #expect(viewModel.isShowingSuggestions)
        guard case .suggestions(let id) = viewModel.pages[7] else {
            Issue.record("carrousel attendu après la 7e vidéo")
            return
        }
        #expect(viewModel.currentEntryID == id)
    }

    @Test("rechargement : les emplacements repartent de la première vidéo")
    func reload() async {
        let viewModel = await makeViewModel([
            .success(page(ids(5), next: "c1")), .success(page(ids(5, from: 6), next: "c2")), .success(page(ids(9), next: "c1")),
        ])
        await viewModel.start()
        viewModel.setShowsSuggestions(true)
        await viewModel.loadMore()
        #expect(viewModel.pages.count == 11)
        await viewModel.reload()
        #expect(viewModel.pages.count == 10)
    }
}
