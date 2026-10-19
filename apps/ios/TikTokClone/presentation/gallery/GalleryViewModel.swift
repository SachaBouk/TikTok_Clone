import CoreGraphics
import Foundation
import Observation

// Galerie maison de la création (ADR-062) : « Récents » ou un album, onglets (« Tout | Vidéos | Photos » en mode Story,
// vidéos seules sinon), sélection numérotée de plusieurs vidéos (dans l'ordre des touchers), ou d'un seul média pour une
// story. L'autorisation d'accès aux Photos est demandée à l'ouverture.
@MainActor
@Observable
final class GalleryViewModel {
    // Au plus 35 vidéos à la fois, comme TikTok.
    static let maxSelection = 35

    let kind: PublicationKind
    private(set) var access: MediaLibraryAccess = .notDetermined
    private(set) var assets: [LibraryAsset] = []
    private(set) var albums: [LibraryAlbum] = []
    private(set) var album: LibraryAlbum?
    private(set) var filter: LibraryFilter
    private(set) var selection: [LibraryAsset] = []
    private(set) var isLoading = false
    private(set) var thumbnails: [String: CGImage] = [:]
    // « Sélectionner plusieurs » (vidéos seulement) ; sinon, un toucher choisit le média et passe à la suite.
    var selectsMultiple: Bool
    var errorMessage: String?

    private let library: any MediaLibrary
    // Ordre de chargement des miniatures : les plus anciennes sont oubliées au-delà de `maxThumbnails`.
    private var thumbnailOrder: [String] = []
    private static let maxThumbnails = 300

    init(kind: PublicationKind, library: any MediaLibrary) {
        self.kind = kind
        self.library = library
        filter = kind == .story ? .all : .videos
        selectsMultiple = kind == .video
    }

    // Onglets proposés : une vidéo ne peut pas être une photo.
    var filters: [LibraryFilter] { kind == .story ? LibraryFilter.allCases : [.videos] }
    var albumTitle: String { album?.title ?? "Récents" }
    var canContinue: Bool { !selection.isEmpty }
    var selectedDuration: Duration { selection.reduce(.zero) { $0 + ($1.duration ?? .zero) } }

    func start() async {
        access = library.access()
        if access == .notDetermined { access = await library.requestAccess() }
        await reload()
    }

    // Retour au premier plan, ou accès limité modifié : la galerie est relue.
    func reload() async {
        access = library.access()
        guard access.canRead else {
            assets = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        async let loadedAssets = library.assets(in: album, filter: filter)
        async let loadedAlbums = library.albums()
        assets = await loadedAssets
        albums = await loadedAlbums
        // Médias disparus de la galerie : retirés de la sélection.
        let ids = Set(assets.map(\.id))
        selection.removeAll { !ids.contains($0.id) }
    }

    func select(album: LibraryAlbum?) async {
        guard album != self.album else { return }
        self.album = album
        await reload()
    }

    func select(filter: LibraryFilter) async {
        guard filter != self.filter, filters.contains(filter) else { return }
        self.filter = filter
        await reload()
    }

    // Numéro dans la sélection (1, 2…), nil si le média n'est pas choisi.
    func number(of asset: LibraryAsset) -> Int? {
        selection.firstIndex(of: asset).map { $0 + 1 }
    }

    // Toucher un média : ajouté ou retiré de la sélection. Faux s'il doit être choisi seul (« Sélectionner plusieurs »
    // décoché, ou story) : l'écran passe alors à la suite avec lui.
    @discardableResult
    func toggle(_ asset: LibraryAsset) -> Bool {
        guard selectsMultiple, asset.isVideo else {
            selection = [asset]
            return false
        }
        if let index = selection.firstIndex(of: asset) {
            selection.remove(at: index)
        } else if selection.count >= Self.maxSelection {
            errorMessage = "\(Self.maxSelection) vidéos au plus."
        } else {
            selection.append(asset)
        }
        return true
    }

    func remove(_ asset: LibraryAsset) {
        selection.removeAll { $0 == asset }
    }

    func setSelectsMultiple(_ multiple: Bool) {
        selectsMultiple = multiple && kind == .video
        if !selectsMultiple, selection.count > 1 { selection = Array(selection.prefix(1)) }
    }

    func loadThumbnail(of asset: LibraryAsset, side: Double) async {
        guard thumbnails[asset.id] == nil, let image = await library.thumbnail(of: asset, side: side) else { return }
        thumbnails[asset.id] = image
        thumbnailOrder.append(asset.id)
        while thumbnailOrder.count > Self.maxThumbnails {
            thumbnails[thumbnailOrder.removeFirst()] = nil
        }
    }
}
