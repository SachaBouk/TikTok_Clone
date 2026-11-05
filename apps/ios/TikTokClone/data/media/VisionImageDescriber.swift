import Foundation
import ImageIO
import Vision

// Description automatique d'une miniature avec Vision, sur l'iPhone (ADR-076) : visages, scène et texte incrusté.
// Rien n'est envoyé ; chaque analyse qui échoue (simulateur sans moteur neuronal…) est simplement ignorée.
struct VisionImageDescriber: ImageDescriber {
    /// Confiance minimale d'une étiquette de scène.
    static let minimumConfidence: Float = 0.3

    func analyze(imageAt url: URL) async throws -> ImageAnalysis {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw CocoaError(.fileReadCorruptFile) }
            return Self.analyze(image)
        }.value
    }

    private static func analyze(_ image: CGImage) -> ImageAnalysis {
        let faces = VNDetectFaceRectanglesRequest()
        let scenes = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ["fr-FR", "en-US"]
        text.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        for request in [faces, scenes, text] as [VNRequest] {
            try? handler.perform([request])
        }
        let identifiers = (scenes.results ?? [])
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .map(\.identifier)
        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first }.filter { $0.confidence >= 0.5 }.map(\.string)
        return ImageAnalysis(
            faces: faces.results?.count ?? 0,
            sceneIdentifiers: identifiers,
            recognizedText: lines.isEmpty ? nil : lines.joined(separator: " ")
        )
    }
}
