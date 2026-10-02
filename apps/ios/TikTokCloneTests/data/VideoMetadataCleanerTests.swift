import AVFoundation
import CoreVideo
import Foundation
import Testing

@testable import TikTokClone

// Vrai AVFoundation, sur une vidéo écrite pour le test : position GPS au format d'un iPhone, rotation d'un quart de tour.
@Suite("Nettoyage des métadonnées d'une vidéo (AVFoundation)")
struct VideoMetadataCleanerTests {
    private static let location = "+48.8566+002.3522+035.000/"

    @Test("position retirée, rotation et durée gardées, original supprimé, sortie en .mov")
    func removesLocation() async throws {
        let directory = URL.temporaryDirectory.appending(path: "cleaner-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.mp4")
        try await Self.writeVideo(to: source)
        #expect(try await Self.locations(in: source) == [Self.location])

        let cleaned = try await AVFoundationVideoMetadataCleaner().clean(source)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(cleaned.pathExtension == "mov")
        #expect(try await Self.locations(in: cleaned).isEmpty)
        let asset = AVURLAsset(url: cleaned)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let transform = try await track.load(.preferredTransform)
        // Quart de tour (a = 0, b = 1, c = -1, d = 0), au flottant près.
        #expect(abs(transform.a) < 0.001 && abs(transform.b - 1) < 0.001 && abs(transform.c + 1) < 0.001 && abs(transform.d) < 0.001)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 0.5) < 0.05)
    }

    @Test("fichier illisible : erreur, et le fichier reçu est supprimé")
    func invalidFile() async throws {
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("pas une vidéo".utf8).write(to: file)
        await #expect(throws: (any Error).self) { try await AVFoundationVideoMetadataCleaner().clean(file) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // Toutes les valeurs de position, quel que soit l'espace de clés (QuickTime, commun, ISO 6709).
    private static func locations(in file: URL) async throws -> [String] {
        let asset = AVURLAsset(url: file)
        var items = try await asset.load(.metadata)
        for format in try await asset.load(.availableMetadataFormats) {
            items += try await asset.loadMetadata(for: format)
        }
        var values: [String] = []
        for item in items where item.identifier == .quickTimeMetadataLocationISO6709 || item.commonKey == .commonKeyLocation {
            if let value = try await item.load(.stringValue) { values.append(value) }
        }
        return Array(Set(values))
    }

    // 15 images de 64 × 64 à 30 i/s, en H.264, avec la position et le fabricant comme un iPhone.
    private static func writeVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
            ])
        input.expectsMediaDataInRealTime = false
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ])
        writer.add(input)
        writer.metadata = [
            metadataItem(.quickTimeMetadataLocationISO6709, location),
            metadataItem(.quickTimeMetadataMake, "Apple"),
        ]
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            #expect(adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 15, timescale: 30))
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }
}
