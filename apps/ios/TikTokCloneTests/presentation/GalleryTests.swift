import CoreGraphics
import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Galerie de la création (ADR-062)")
struct GalleryTests {
    private func video(_ id: String, _ seconds: Int = 10) -> LibraryAsset {
        LibraryAsset(id: id, isVideo: true, duration: .seconds(seconds))
    }

    private func photo(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, isVideo: false, duration: nil)
    }

    @Test("autorisation demandée à l'ouverture ; refusée : rien n'est lu")
    func access() async {
        let library = FakeMediaLibrary()
        library.items = [video("a")]
        library.grantedAccess = .denied
        let model = GalleryViewModel(kind: .video, library: library)
        await model.start()
        #expect(library.requests == 1)
        #expect(model.access == .denied && model.assets.isEmpty)

        library.accessState = .limited
        await model.reload()
        #expect(model.access == .limited && model.assets == [video("a")])
    }

    @Test("mode Caméra : vidéos seules, sélection numérotée dans l'ordre des touchers, retirée, Suivant (N)")
    func multipleSelection() async {
        let library = FakeMediaLibrary()
        library.accessState = .full
        library.items = [video("a"), photo("p"), video("b", 22), video("c")]
        let model = GalleryViewModel(kind: .video, library: library)
        await model.start()
        #expect(library.requests == 0)
        #expect(model.filters == [.videos])
        #expect(model.assets.map(\.id) == ["a", "b", "c"])
        #expect(model.selectsMultiple && !model.canContinue)

        #expect(model.toggle(video("b", 22)))
        #expect(model.toggle(video("a")))
        #expect(model.number(of: video("b", 22)) == 1 && model.number(of: video("a")) == 2)
        #expect(model.selectedDuration == .seconds(32))
        model.toggle(video("b", 22))
        #expect(model.number(of: video("a")) == 1 && model.number(of: video("b", 22)) == nil)
        model.remove(video("a"))
        #expect(!model.canContinue)

        // « Sélectionner plusieurs » décoché : un toucher choisit la vidéo seule et passe à la suite.
        model.setSelectsMultiple(false)
        #expect(!model.toggle(video("c")))
        #expect(model.selection == [video("c")])
    }

    @Test("au plus 35 vidéos à la fois")
    func selectionLimit() async {
        let library = FakeMediaLibrary()
        library.accessState = .full
        library.items = (0...GalleryViewModel.maxSelection).map { video("v\($0)") }
        let model = GalleryViewModel(kind: .video, library: library)
        await model.start()
        for asset in model.assets { model.toggle(asset) }
        #expect(model.selection.count == GalleryViewModel.maxSelection)
        #expect(model.errorMessage == "35 vidéos au plus.")
    }

    @Test("mode Story : Tout, Vidéos, Photos ; un seul média ; albums ; miniatures gardées")
    func storyAndAlbums() async {
        let library = FakeMediaLibrary()
        library.accessState = .full
        library.items = [video("a"), photo("p")]
        let favorites = LibraryAlbum(id: "fav", title: "Favoris", count: 1)
        library.albumList = [favorites]
        library.albumItems = ["fav": [photo("p")]]
        let model = GalleryViewModel(kind: .story, library: library)
        await model.start()
        #expect(model.filters == [.all, .videos, .photos] && model.filter == .all)
        #expect(model.assets.count == 2 && !model.selectsMultiple)
        #expect(!model.toggle(photo("p")))
        #expect(model.selection == [photo("p")])

        await model.select(filter: .videos)
        #expect(model.assets == [video("a")])
        // Le média choisi n'est plus dans la liste : retiré de la sélection.
        #expect(model.selection.isEmpty)
        await model.select(filter: .all)
        await model.select(album: favorites)
        #expect(model.albumTitle == "Favoris" && model.assets == [photo("p")])

        await model.loadThumbnail(of: photo("p"), side: 100)
        await model.loadThumbnail(of: photo("p"), side: 100)
        #expect(model.thumbnails["p"] != nil)
        #expect(library.thumbnailRequests == ["p"])
    }

    @Test("durées de la galerie : minutes et secondes")
    func durationLabel() {
        #expect(GalleryDuration.label(.seconds(50)) == "00:50")
        #expect(GalleryDuration.label(.milliseconds(137_400)) == "02:17")
    }
}
