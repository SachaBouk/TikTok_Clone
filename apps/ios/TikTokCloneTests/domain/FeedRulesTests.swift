import Testing

@testable import TikTokClone

@Suite("Règles du lecteur")
struct FeedRulesTests {
    @Test(
        "fenêtre de préchargement : courante, suivante, précédente, dans les bornes",
        arguments: [
            (0, 5, [0, 1]),
            (2, 5, [2, 3, 1]),
            (4, 5, [4, 3]),
            (0, 1, [0]),
        ])
    func window(index: Int, count: Int, expected: [Int]) {
        #expect(PreloadPolicy.window(around: index, count: count) == expected)
    }

    @Test("page suivante chargée quand il reste 3 vidéos ou moins après la courante")
    func loadMore() {
        #expect(!PreloadPolicy.shouldLoadMore(currentIndex: 0, count: 10))
        #expect(!PreloadPolicy.shouldLoadMore(currentIndex: 5, count: 10))
        #expect(PreloadPolicy.shouldLoadMore(currentIndex: 6, count: 10))
        #expect(PreloadPolicy.shouldLoadMore(currentIndex: 0, count: 2))
    }

    @Test("une vue comptée une seule fois par vidéo")
    func viewTracker() {
        var tracker = ViewTracker()
        #expect(tracker.needsRecording("a"))
        tracker.markRecorded("a")
        #expect(!tracker.needsRecording("a"))
        #expect(tracker.needsRecording("b"))
    }

    @Test("pastille de republication : « Republier », « Tu as republié », rien sur sa propre vidéo")
    func repostBadge() {
        #expect(RepostBadge.of(.sample("v1", viewer: .empty), isOwn: false) == .repost)
        #expect(RepostBadge.of(.sample("v1", viewer: ViewerState.empty.with(.repost, active: true)), isOwn: false) == .reposted)
        // Invité : « Republier » (la connexion s'ouvre au toucher).
        #expect(RepostBadge.of(.sample("v1", viewer: nil), isOwn: false) == .repost)
        #expect(RepostBadge.of(.sample("v1", viewer: .empty), isOwn: true) == nil)
    }

    @Test("barre de progression : part lue entre 0 et 1, rien tant que la durée est inconnue")
    func progressFraction() {
        #expect(PlaybackProgress(position: .seconds(5), duration: .seconds(20)).fraction == 0.25)
        #expect(PlaybackProgress(position: .seconds(25), duration: .seconds(20)).fraction == 1)
        #expect(PlaybackProgress(position: .zero, duration: .seconds(20)).fraction == 0)
        #expect(PlaybackProgress(position: .seconds(5), duration: nil).fraction == nil)
        #expect(PlaybackProgress(position: .seconds(5), duration: .zero).fraction == nil)
    }
}

@Suite("Cadrage d'une vidéo plein écran")
struct VideoFramingTests {
    @Test("verticale (9:16, 2:3) : remplit ; carrée, 3:4 ou horizontale : ajustée sur fond noir")
    func framing() {
        #expect(VideoFraming.fills(width: 1080, height: 1920))
        #expect(VideoFraming.fills(width: 720, height: 1080))
        #expect(!VideoFraming.fills(width: 1000, height: 1000))
        #expect(!VideoFraming.fills(width: 1000, height: 932))
        #expect(!VideoFraming.fills(width: 836, height: 1000))
        #expect(!VideoFraming.fills(width: 1080, height: 1440))
        #expect(!VideoFraming.fills(width: 1920, height: 1080))
    }

    @Test("taille inconnue : remplit, comme avant")
    func unknownSize() {
        #expect(VideoFraming.fills(width: 0, height: 0))
        #expect(VideoFraming.fills(width: 1080, height: 0))
    }
}
