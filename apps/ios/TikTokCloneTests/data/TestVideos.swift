import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Testing

// Vidéos écrites pour les tests (vrai AVFoundation) : un fond uni, un repère rouge dans le quart en haut à gauche (pour
// vérifier la rotation), un son facultatif (440 Hz), une position GPS facultative au format d'un iPhone.
enum TestVideos {
    struct Color {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    static let marker = Color(red: 230, green: 20, blue: 20)
    static let location = "+48.8566+002.3522+035.000/"

    static func directory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "edit-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // `width` × `height` : taille enregistrée ; `transform` : rotation de la piste (taille affichée tournée).
    static func write(
        to url: URL, width: Int = 160, height: Int = 96, seconds: Double = 2, fps: Int = 30, background: Color = Color(red: 30, green: 90, blue: 200),
        transform: CGAffineTransform = .identity, audio: Bool = false, withLocation: Bool = false
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(
            mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        video.expectsMediaDataInRealTime = false
        video.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: video,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(video)
        var audioInput: AVAssetWriterInput?
        if audio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }
        if withLocation {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataLocationISO6709
            item.value = location as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            writer.metadata = [item]
        }
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        // Pistes écrites en alternance : l'écrivain les entrelace, et attend l'une pour l'autre.
        let frames = Int(seconds * Double(fps))
        let sampleRate = 44_100
        let chunk = 4_410
        let samples = audioInput == nil ? 0 : Int(seconds * Double(sampleRate))
        var frame = 0
        var written = 0
        var idle = 0
        let pool = try #require(adaptor.pixelBufferPool)
        while frame < frames || written < samples {
            if writer.status == .failed { throw try #require(writer.error) }
            // Garde-fou : 10 s sans rien pouvoir écrire, le test échoue au lieu de rester bloqué.
            if idle > 5_000 {
                throw CocoaError(
                    .fileWriteUnknown,
                    userInfo: [NSDebugDescriptionErrorKey: "écriture bloquée : \(frame)/\(frames) images, \(written)/\(samples) échantillons"])
            }
            // La piste en retard d'abord ; si elle n'est pas prête, l'autre (l'écrivain veut de l'avance sur l'une ou l'autre).
            let videoBehind = written >= samples || Double(frame) / Double(fps) <= Double(written) / Double(sampleRate)
            let videoReady = frame < frames && video.isReadyForMoreMediaData
            let audioReady = written < samples && audioInput?.isReadyForMoreMediaData == true
            if videoReady && (videoBehind || !audioReady) {
                let buffer = try pixelBuffer(width: width, height: height, background: background, pool: pool)
                #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))))
                frame += 1
                if frame == frames { video.markAsFinished() }
            } else if audioReady, let audioInput {
                let count = min(chunk, samples - written)
                #expect(audioInput.append(try toneBuffer(start: written, count: count, sampleRate: sampleRate)))
                written += count
                if written == samples { audioInput.markAsFinished() }
            } else {
                idle += 1
                try await Task.sleep(for: .milliseconds(2))
                continue
            }
            idle = 0
        }
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    // Couleur du pixel (x, y) de l'image affichée à `seconds` (rotation appliquée), en proportions de l'image.
    static func color(in url: URL, at seconds: Double, x: Double, y: Double) async throws -> Color {
        let image = try await frame(of: url, at: seconds)
        return try pixel(of: image, x: Int(x * Double(image.width)), y: Int(y * Double(image.height)))
    }

    static func frame(of url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func pixel(of image: CGImage, x: Int, y: Int) throws -> Color {
        var data = [UInt8](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // L'image est dessinée décalée pour que le pixel voulu (origine en haut à gauche) tombe sur le seul pixel du contexte.
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return Color(red: data[0], green: data[1], blue: data[2])
    }

    static func displaySize(of url: URL) async throws -> CGSize {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    static func hasAudio(_ url: URL) async throws -> Bool {
        !(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)).isEmpty
    }

    // Toutes les valeurs de position, quel que soit l'espace de clés.
    static func locations(in url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
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

    private static func pixelBuffer(width: Int, height: Int, background: Color, pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
        let buffer = try #require(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            for column in 0..<width {
                let color = row < height / 2 && column < width / 2 ? marker : background
                let pixel = base + row * bytesPerRow + column * 4
                pixel[0] = color.blue
                pixel[1] = color.green
                pixel[2] = color.red
                pixel[3] = 255
            }
        }
        return buffer
    }

    private static func toneBuffer(start: Int, count: Int, sampleRate: Int) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(
            CMAudioFormatDescriptionCreate(
                allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                formatDescriptionOut: &format) == noErr)
        var samples = (0..<count).map { index -> Int16 in
            Int16(8000 * sin(2 * Double.pi * 440 * Double(start + index) / Double(sampleRate)))
        }
        var block: CMBlockBuffer?
        let length = count * 2
        #expect(
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                dataLength: length,
                flags: 0, blockBufferOut: &block) == noErr)
        let blockBuffer = try #require(block)
        samples.withUnsafeMutableBytes { bytes in
            _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length)
        }
        var sample: CMSampleBuffer?
        #expect(
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: blockBuffer, formatDescription: try #require(format), sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)), packetDescriptions: nil,
                sampleBufferOut: &sample)
                == noErr)
        return try #require(sample)
    }
}
