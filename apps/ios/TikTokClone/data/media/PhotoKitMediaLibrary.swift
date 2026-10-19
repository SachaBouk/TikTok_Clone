import Photos
import UIKit

// Galerie de l'appareil par PhotoKit (ADR-062). Les vidéos sont copiées depuis leur ressource d'origine (la version
// modifiée dans Photos si elle existe), téléchargées d'iCloud au besoin ; leurs métadonnées sont retirées ensuite par la
// préparation de la publication (ADR-035).
struct PhotoKitMediaLibrary: MediaLibrary {
    func access() -> MediaLibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> MediaLibraryAccess {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func albums() async -> [LibraryAlbum] {
        var albums: [LibraryAlbum] = []
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        for result in [smart, user] {
            result.enumerateObjects { collection, _, _ in
                // « Récents » est l'entrée par défaut ; les albums masqués ou récemment supprimés ne sont pas proposés.
                guard collection.assetCollectionSubtype != .smartAlbumUserLibrary,
                    collection.assetCollectionSubtype != .smartAlbumAllHidden,
                    collection.assetCollectionSubtype.rawValue != 1_000_000_201
                else { return }
                let count = PHAsset.fetchAssets(in: collection, options: Self.options(filter: .all)).count
                if count > 0 {
                    albums.append(LibraryAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album", count: count))
                }
            }
        }
        return albums
    }

    func assets(in album: LibraryAlbum?, filter: LibraryFilter) async -> [LibraryAsset] {
        let options = Self.options(filter: filter)
        let result: PHFetchResult<PHAsset>
        if let album, let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }
        var assets: [LibraryAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            let isVideo = asset.mediaType == .video
            assets.append(
                LibraryAsset(
                    id: asset.localIdentifier, isVideo: isVideo, duration: isVideo ? .milliseconds(Int64(asset.duration * 1000)) : nil))
        }
        return assets
    }

    func thumbnail(of asset: LibraryAsset, side: Double) async -> CGImage? {
        guard let phAsset = Self.asset(asset.id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: phAsset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    func exportVideo(_ asset: LibraryAsset) async throws -> URL {
        guard let phAsset = Self.asset(asset.id) else { throw CocoaError(.fileNoSuchFile) }
        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo }) ?? resources.first(where: { $0.type == .video }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let directory = URL.temporaryDirectory.appending(path: "Picked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = URL(filePath: resource.originalFilename).pathExtension.lowercased()
        let destination = directory.appending(path: "\(UUID().uuidString).\(fileExtension.isEmpty ? "mov" : fileExtension)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)
        return destination
    }

    func photoData(_ asset: LibraryAsset) async throws -> Data {
        guard let phAsset = Self.asset(asset.id) else { throw CocoaError(.fileNoSuchFile) }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: phAsset, options: options) { data, _, _, _ in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: CocoaError(.fileReadCorruptFile)) }
            }
        }
    }

    private static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private static func options(filter: LibraryFilter) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch filter {
        case .all:
            options.predicate = NSPredicate(
                format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.video.rawValue, PHAssetMediaType.image.rawValue)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        case .photos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }
        return options
    }

    private static func map(_ status: PHAuthorizationStatus) -> MediaLibraryAccess {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
