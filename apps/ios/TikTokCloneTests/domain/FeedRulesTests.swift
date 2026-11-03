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

@Suite("Plein écran d'une vidéo horizontale")
struct FullScreenRulesTests {
    @Test("proposé pour une vidéo 4:3 ou 16:9, pas pour une carrée, verticale ou de taille inconnue")
    func offered() {
        #expect(VideoFraming.offersFullScreen(width: 1920, height: 1080))
        #expect(VideoFraming.offersFullScreen(width: 1440, height: 1080))
        #expect(!VideoFraming.offersFullScreen(width: 1000, height: 1000))
        #expect(!VideoFraming.offersFullScreen(width: 1000, height: 932))
        #expect(!VideoFraming.offersFullScreen(width: 1080, height: 1920))
        #expect(!VideoFraming.offersFullScreen(width: 0, height: 0))
    }

    @Test("iPhone tourné sur la vidéo affichée : plein écran ; remis droit : retour ; à plat : rien")
    func rotation() {
        #expect(LandscapeRotation.entersFullScreen(tilt: .landscape, offersFullScreen: true, isCurrent: true))
        #expect(!LandscapeRotation.entersFullScreen(tilt: .landscape, offersFullScreen: false, isCurrent: true))
        #expect(!LandscapeRotation.entersFullScreen(tilt: .landscape, offersFullScreen: true, isCurrent: false))
        #expect(!LandscapeRotation.entersFullScreen(tilt: .other, offersFullScreen: true, isCurrent: true))
        #expect(LandscapeRotation.leavesFullScreen(tilt: .portrait))
        #expect(!LandscapeRotation.leavesFullScreen(tilt: .other))
        #expect(!LandscapeRotation.leavesFullScreen(tilt: .landscape))
    }
}

@Suite("Barre de progression qu'on fait glisser")
struct PlaybackScrubTests {
    @Test("position sous le doigt, bornée à la vidéo")
    func fraction() {
        #expect(PlaybackScrub.fraction(x: 100, width: 400) == 0.25)
        #expect(PlaybackScrub.fraction(x: -20, width: 400) == 0)
        #expect(PlaybackScrub.fraction(x: 500, width: 400) == 1)
        #expect(PlaybackScrub.fraction(x: 10, width: 0) == 0)
    }

    @Test("temps visé et durée affichés en grand")
    func labels() {
        let labels = PlaybackScrub.labels(fraction: 0.5, duration: .seconds(11))
        #expect(labels.position == "00:05")
        #expect(labels.duration == "00:11")
        #expect(PlaybackScrub.labels(fraction: 1, duration: .seconds(125)) == ("02:05", "02:05"))
        #expect(PlaybackScrub.labels(fraction: 0.3, duration: nil) == ("00:00", "00:00"))
    }
}

@Suite("Balayage vers le profil de l'auteur")
struct AuthorSwipeTests {
    @Test("part du profil entrée, d'après le doigt vers la gauche")
    func progress() {
        #expect(AuthorSwipe.progress(translation: -100, width: 400) == 0.25)
        #expect(AuthorSwipe.progress(translation: 50, width: 400) == 0)
        #expect(AuthorSwipe.progress(translation: -800, width: 400) == 1)
    }

    @Test("ouvert au-delà d'un tiers ou sur un balayage rapide ; sinon il repart")
    func completes() {
        #expect(AuthorSwipe.completes(progress: 0.4, velocity: 0))
        #expect(!AuthorSwipe.completes(progress: 0.2, velocity: -100))
        #expect(AuthorSwipe.completes(progress: 0.1, velocity: -900))
        #expect(!AuthorSwipe.completes(progress: 0.02, velocity: -900))
        #expect(!AuthorSwipe.completes(progress: 0.2, velocity: 800))
    }
}
