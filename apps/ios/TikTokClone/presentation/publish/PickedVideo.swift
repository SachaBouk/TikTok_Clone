import AVFoundation
import CoreTransferable
import UIKit
import UniformTypeIdentifiers

// Vidéo choisie dans la galerie (PhotosPicker), copiée dans un fichier temporaire : le fichier reçu n'est
// valable que pendant l'import. Le cas d'usage de publication le déplace ensuite dans le stockage des envois.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = URL.temporaryDirectory.appending(path: "Picked", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension.lowercased()
            let destination = directory.appending(path: "\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}

// Aperçu d'une vidéo locale : première image (rotation appliquée) et durée.
enum VideoPreview {
    static func image(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: image)
    }

    static func duration(of url: URL) async -> Duration? {
        guard let time = try? await AVURLAsset(url: url).load(.duration), time.isNumeric else { return nil }
        return .milliseconds(Int64(time.seconds * 1000))
    }
}
