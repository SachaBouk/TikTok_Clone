import SwiftUI
import UIKit

// Miniatures des vidéos gardées en mémoire (grilles du profil) : une miniature déjà chargée s'affiche aussitôt, sans le
// carré gris d'`AsyncImage` (qui recharge à chaque nouvelle vue : la grille clignotait à l'ouverture d'un profil
// préparé pendant le balayage vers l'auteur, `authorProfileSwipe`).
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images = NSCache<NSURL, UIImage>()

    private init() {
        images.countLimit = 300
    }

    func image(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    // Chargée par le cache d'URL partagé, gardée en mémoire ; nil si illisible.
    @discardableResult
    func load(_ url: URL) async -> UIImage? {
        if let image = image(for: url) { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    // Charge d'avance plusieurs miniatures, en parallèle.
    func preload(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls where image(for: url) == nil {
                group.addTask { await self.load(url) }
            }
        }
    }
}

// Miniature d'une grille : celle du cache tout de suite, sinon chargée (fond gris en attendant).
struct CachedThumbnail: View {
    let url: URL
    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? ThumbnailCache.shared.image(for: url)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .task(id: url) {
            guard ThumbnailCache.shared.image(for: url) == nil else { return }
            loaded = await ThumbnailCache.shared.load(url)
        }
    }
}
