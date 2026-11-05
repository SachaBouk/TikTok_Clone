import SwiftUI
import UIKit

// Miniature d'une vidéo plein écran, cadrée comme la vidéo (`VideoFraming`) : verticale, elle remplit ; carrée ou
// horizontale, elle est montrée entière sur fond noir. `AsyncImage` ne donne pas la taille de l'image, d'où ce
// chargement (par le cache d'URL partagé, comme `AsyncImage`).
struct FramedThumbnail<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                let picture = Image(uiImage: image).resizable()
                if VideoFraming.fills(width: image.size.width, height: image.size.height) {
                    picture.scaledToFill()
                } else {
                    picture.scaledToFit()
                }
            } else {
                placeholder()
            }
        }
        // Décor : la vidéo est décrite par son élément (ADR-076).
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            image = UIImage(data: data)
        }
    }
}
