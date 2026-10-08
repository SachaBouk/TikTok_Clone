import Foundation
import UIKit

// Photo d'une story (ADR-051) : décodée avec son orientation, recadrée au centre en 9:16, redessinée en 1080×1920 et
// réencodée en JPEG. Le réencodage n'écrit que les pixels : ni EXIF, ni position GPS, ni appareil (comme les vidéos,
// ADR-035).
struct UIKitStoryPhotoRenderer: StoryPhotoRenderer {
    var quality: CGFloat = 0.85

    func render(_ imageData: Data) async throws -> URL {
        guard let image = UIImage(data: imageData) else { throw AppError.unexpected }
        // Pixels orientés (une photo d'iPhone est souvent stockée couchée, avec une orientation EXIF).
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let crop = StoryRules.cropRect(for: pixelSize)
        guard crop.width > 0 else { throw AppError.unexpected }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = StoryRules.photoSize
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // Le recadrage, exprimé en pixels orientés, est ramené à l'échelle de la sortie.
            let factor = size.width / crop.width
            image.draw(
                in: CGRect(
                    x: -crop.minX * factor, y: -crop.minY * factor, width: pixelSize.width * factor,
                    height: pixelSize.height * factor))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= StoryRules.maxPhotoFileSize else {
            throw AppError.unexpected
        }
        let directory = URL.temporaryDirectory.appending(path: "Picked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).jpg")
        try jpeg.write(to: url)
        return url
    }
}
