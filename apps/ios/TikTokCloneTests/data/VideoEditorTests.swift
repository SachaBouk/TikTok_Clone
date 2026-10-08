import AVFoundation
import CoreImage
import Foundation
import Testing
import UIKit

@testable import TikTokClone

// Vrai AVFoundation et Core Image, sur des vidéos écrites pour le test (`TestVideos`) : export sans réencodage,
// assemblage de segments tournés différemment, vitesse, filtres, textes, métadonnées (ADR-052, ADR-035).
@Suite("Export d'une vidéo modifiée (AVFoundation)", .serialized)
struct VideoEditorTests {
    private static let quarterTurn = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0)
    private let editor = AVFoundationVideoEditor()

    private func clip(_ url: URL) async throws -> SourceClip {
        SourceClip(file: url, duration: .seconds(try await TestVideos.duration(of: url)))
    }

    private func isRed(_ color: TestVideos.Color) -> Bool {
        color.red > 150 && color.green < 90 && color.blue < 90
    }

    @Test("découpage seul : sans réencodage, intervalle gardé, rotation gardée, position retirée, sources intactes")
    func passthroughTrim() async throws {
        let directory = try TestVideos.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        try await TestVideos.write(to: source, transform: Self.quarterTurn, audio: true, withLocation: true)
        #expect(try await TestVideos.locations(in: source) == [TestVideos.location])

        var plan = EditPlan(clips: [try await clip(source)], kind: .video)
        plan.setTrimStart(.milliseconds(500))
        plan.setTrimEnd(.milliseconds(1500))
        #expect(!plan.needsReencoding)
        let output = try await editor.export(plan)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(output.pathExtension == "mov")
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(abs(try await TestVideos.duration(of: output) - 1) < 0.1)
        #expect(try await TestVideos.locations(in: output).isEmpty)
        #expect(try await TestVideos.displaySize(of: output) == CGSize(width: 96, height: 160))
        #expect(try await TestVideos.hasAudio(output))
        // Repère en haut à gauche de l'image enregistrée : en haut à droite une fois tournée d'un quart de tour.
        #expect(isRed(try await TestVideos.color(in: output, at: 0.5, x: 0.75, y: 0.25)))
        #expect(!isRed(try await TestVideos.color(in: output, at: 0.5, x: 0.25, y: 0.75)))
    }

    @Test("segments assemblés : rotation propre à chacun, durée cumulée, son, sans position")
    func concatenation() async throws {
        let directory = try TestVideos.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rotated = directory.appending(path: "rotated.mov")
        let upright = directory.appending(path: "upright.mov")
        try await TestVideos.write(to: rotated, seconds: 1, transform: Self.quarterTurn, audio: true, withLocation: true)
        try await TestVideos.write(to: upright, width: 96, height: 160, seconds: 1, audio: true)

        let plan = EditPlan(clips: [try await clip(rotated), try await clip(upright)], kind: .video)
        #expect(plan.needsReencoding)
        let output = try await editor.export(plan)
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(abs(try await TestVideos.duration(of: output) - 2) < 0.15)
        #expect(try await TestVideos.displaySize(of: output) == CGSize(width: 96, height: 160))
        #expect(try await TestVideos.hasAudio(output))
        #expect(try await TestVideos.locations(in: output).isEmpty)
        // Premier segment (tourné) : repère en haut à droite ; second (droit) : en haut à gauche.
        #expect(isRed(try await TestVideos.color(in: output, at: 0.5, x: 0.75, y: 0.25)))
        #expect(isRed(try await TestVideos.color(in: output, at: 1.5, x: 0.25, y: 0.25)))
        #expect(!isRed(try await TestVideos.color(in: output, at: 1.5, x: 0.75, y: 0.25)))
    }

    @Test("vitesse 2× et découpage : durée finale, son gardé")
    func speedAndTrim() async throws {
        let directory = try TestVideos.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        try await TestVideos.write(to: source, seconds: 3, audio: true)

        var plan = EditPlan(clips: [try await clip(source)], kind: .video)
        plan.setTrimStart(.seconds(1))
        plan.speed = .double
        #expect(plan.outputDuration == .seconds(1))
        let output = try await editor.export(plan)
        defer { try? FileManager.default.removeItem(at: output) }
        #expect(abs(try await TestVideos.duration(of: output) - 1) < 0.15)
        #expect(try await TestVideos.hasAudio(output))

        plan.speed = .half
        let slow = try await editor.export(plan)
        defer { try? FileManager.default.removeItem(at: slow) }
        #expect(abs(try await TestVideos.duration(of: slow) - 4) < 0.15)
    }

    @Test("filtres : noir et blanc sans couleur, chaud plus rouge que froid")
    func filters() async throws {
        let directory = try TestVideos.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        try await TestVideos.write(to: source, width: 96, height: 160, seconds: 1)

        func background(_ filter: VideoFilter) async throws -> TestVideos.Color {
            var plan = EditPlan(clips: [try await clip(source)], kind: .video)
            plan.filter = filter
            plan.speed = filter == .none ? .faster : .normal  // réencodé dans tous les cas
            let output = try await editor.export(plan)
            defer { try? FileManager.default.removeItem(at: output) }
            return try await TestVideos.color(in: output, at: 0.3, x: 0.75, y: 0.75)
        }
        let original = try await background(.none)
        #expect(original.blue > 150 && original.red < 80)
        let mono = try await background(.mono)
        #expect(abs(Int(mono.red) - Int(mono.blue)) < 12 && abs(Int(mono.green) - Int(mono.blue)) < 12)
        let warm = try await background(.warm)
        let cool = try await background(.cool)
        #expect(Int(warm.red) - Int(warm.blue) > Int(cool.red) - Int(cool.blue))
    }

    @Test("textes incrustés à leur place, absents ailleurs")
    func textOverlay() async throws {
        let directory = try TestVideos.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mov")
        try await TestVideos.write(to: source, width: 360, height: 640, seconds: 1)

        var plan = EditPlan(clips: [try await clip(source)], kind: .video)
        let added = plan.addText("MMMM", color: .white, size: .large)
        let text = try #require(added)
        plan.moveText(text.id, to: CGPoint(x: 0.5, y: 0.8))
        let output = try await editor.export(plan)
        defer { try? FileManager.default.removeItem(at: output) }

        let frame = try await TestVideos.frame(of: output, at: 0.5)
        #expect(try Self.whiteShare(in: frame, rows: 0.72...0.88) > 0.05)
        #expect(try Self.whiteShare(in: frame, rows: 0.55...0.65) == 0)
    }

    @Test("rotation d'une image : quart de tour, demi-tour, trois quarts, miroir")
    func orientation() throws {
        let context = CIContext()
        let size = CGSize(width: 40, height: 20)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(origin: .zero, size: size))
        // Repère en haut à gauche (origine de Core Image en bas).
        let marker = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 10, width: 20, height: 10))
        let image = marker.composited(over: background)

        func markerCorner(_ transform: CGAffineTransform) throws -> (CGSize, String) {
            let oriented = EditRendering.oriented(image, transform: transform)
            let rendered = try #require(context.createCGImage(oriented, from: oriented.extent))
            var corners: [String] = []
            for (name, x, y) in [("haut-gauche", 0.25, 0.25), ("haut-droite", 0.75, 0.25), ("bas-gauche", 0.25, 0.75), ("bas-droite", 0.75, 0.75)] {
                let color = try TestVideos.pixel(of: rendered, x: Int(x * Double(rendered.width)), y: Int(y * Double(rendered.height)))
                if color.red > 200 { corners.append(name) }
            }
            return (oriented.extent.size, corners.joined(separator: ","))
        }
        #expect(try markerCorner(.identity) == (size, "haut-gauche"))
        #expect(try markerCorner(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)) == (CGSize(width: 20, height: 40), "haut-droite"))
        #expect(try markerCorner(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)) == (size, "bas-droite"))
        #expect(try markerCorner(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) == (CGSize(width: 20, height: 40), "bas-gauche"))
        #expect(try markerCorner(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0)) == (size, "haut-droite"))
    }

    @Test("taille de rendu : petit côté de 1080 px au plus, jamais agrandie, dimensions paires")
    func renderSize() {
        #expect(EditComposition.renderSize(for: CGSize(width: 2160, height: 3840)) == CGSize(width: 1080, height: 1920))
        #expect(EditComposition.renderSize(for: CGSize(width: 1080, height: 1920)) == CGSize(width: 1080, height: 1920))
        #expect(EditComposition.renderSize(for: CGSize(width: 361, height: 641)) == CGSize(width: 362, height: 642))
        #expect(EditComposition.renderSize(for: CGSize(width: 1920, height: 1440)) == CGSize(width: 1440, height: 1080))
    }

    @Test("aperçu : composition valide, lue par AVPlayer (simplifiée si le lecteur la refuse, comme le simulateur)")
    @MainActor
    func previewPlayable() async throws {
        let directory = try TestVideos.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.mov")
        let second = directory.appending(path: "second.mov")
        try await TestVideos.write(to: first, seconds: 1, transform: Self.quarterTurn, audio: true)
        try await TestVideos.write(to: second, width: 96, height: 160, seconds: 1, audio: true)
        var plan = EditPlan(clips: [try await clip(first), try await clip(second)], kind: .video)
        plan.filter = .mono
        plan.speed = .faster

        let built = try await EditComposition.make(plan, includeTexts: false)
        let composition = built.composition
        let valid = try await built.videoComposition.isValid(
            for: composition, timeRange: CMTimeRange(start: .zero, duration: composition.duration), validationDelegate: ValidationLog.shared)
        #expect(valid, "\(ValidationLog.shared.messages)")

        let preview = EditorPreviewPlayer()
        // Affiché par une vraie couche, dans une fenêtre : c'est l'affichage qui construit le rendu (piège -12784).
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        let layer = AVPlayerLayer(player: preview.player)
        layer.frame = window.bounds
        window.layer.addSublayer(layer)
        window.isHidden = false
        defer { window.isHidden = true }
        await preview.load(plan)
        #expect(!preview.failed)
        let item = try #require(preview.player.currentItem)
        _ = item
        // Le simulateur n'affiche aucune composition vidéo : l'aperçu se relit alors sans elle.
        for _ in 0..<300 where preview.player.currentItem?.status != .readyToPlay {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(preview.player.currentItem?.status == .readyToPlay, "\(String(describing: preview.player.currentItem?.error))")
        if preview.isSimplified { #expect(preview.player.currentItem?.videoComposition == nil) }
        #expect(abs(preview.aspectRatio - 96.0 / 160.0) < 0.001)
        preview.stop()
    }

    @Test("fichier illisible : erreur")
    func invalidFile() async throws {
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("pas une vidéo".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var plan = EditPlan(clips: [SourceClip(file: file, duration: .seconds(2))], kind: .video)
        plan.filter = .mono
        await #expect(throws: (any Error).self) { try await editor.export(plan) }
    }

    // Part des pixels presque blancs dans une bande horizontale de l'image (lignes en proportion de la hauteur).
    private static func whiteShare(in image: CGImage, rows: ClosedRange<Double>) throws -> Double {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var white = 0
        var total = 0
        // Lignes du bitmap de haut en bas (origine du contexte en bas, mémoire en haut).
        for row in Int(rows.lowerBound * Double(height))..<Int(rows.upperBound * Double(height)) {
            for column in 0..<width {
                let index = (row * width + column) * 4
                total += 1
                if data[index] > 200 && data[index + 1] > 200 && data[index + 2] > 200 { white += 1 }
            }
        }
        return total > 0 ? Double(white) / Double(total) : 0
    }
}

final class ValidationLog: NSObject, AVVideoCompositionValidationHandling, @unchecked Sendable {
    static let shared = ValidationLog()
    var messages: [String] = []

    func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool {
        messages.append("clé \(key)")
        return true
    }

    func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingEmptyTimeRange timeRange: CMTimeRange) -> Bool {
        messages.append("vide \(timeRange.start.seconds)-\(timeRange.end.seconds)")
        return true
    }

    func videoComposition(
        _ videoComposition: AVVideoComposition,
        shouldContinueValidatingAfterFindingInvalidTimeRangeIn videoCompositionInstruction: any AVVideoCompositionInstructionProtocol
    ) -> Bool {
        messages.append("intervalle \(videoCompositionInstruction.timeRange.start.seconds)-\(videoCompositionInstruction.timeRange.end.seconds)")
        return true
    }

    func videoComposition(
        _ videoComposition: AVVideoComposition,
        shouldContinueValidatingAfterFindingInvalidTrackIDIn videoCompositionInstruction: any AVVideoCompositionInstructionProtocol,
        layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset
    ) -> Bool {
        messages.append("piste")
        return true
    }
}
