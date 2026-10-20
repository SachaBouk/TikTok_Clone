import AVFoundation
import CoreImage

// Composition AVFoundation d'un plan d'édition (ADR-052, ADR-062), partagée par l'aperçu de l'éditeur et l'export : même
// rendu.
// - clips mis bout à bout sur une piste vidéo et une piste son, chacun avec son intervalle, puis sa vitesse
//   (`scaleTimeRange`, sur toutes les pistes) ;
// - volume de chaque clip par un mixage audio (son d'origine coupé : volume nul partout) ;
// - une instruction par clip, pour le compositeur (`EditCompositor`) : rotation de la piste et du clip, cadre, image
//   ajustée en 9:16, filtre et son intensité, effets sur leurs plages (ADR-063), textes et autocollants.
struct EditComposition {
    // Image finale en 9:16, petit côté de 1080 px au plus (jamais agrandie au-delà du plus grand clip).
    static let maxShortSide: CGFloat = 1080
    static let maxFrameRate: Float = 60

    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVMutableAudioMix?
    let renderSize: CGSize

    private struct Piece {
        let start: CMTime
        let duration: CMTime
        let transform: CGAffineTransform
        let clip: EditClip
        var end: CMTime { start + duration }
    }

    // `includeTexts` faux pour l'aperçu : textes et autocollants y sont dessinés par SwiftUI, déplaçables au doigt.
    static func make(_ plan: EditPlan, includeTexts: Bool) async throws -> sending EditComposition {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.fileWriteUnknown) }

        var pieces: [Piece] = []
        var cursor = CMTime.zero
        var largestShortSide: CGFloat = 0
        var frameRate: Float = 30
        var hasAudio = false
        let audioParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        for clip in plan.clips {
            let asset = AVURLAsset(url: clip.source.file)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
            let (trackRange, transform, naturalSize, nominalFrameRate) = try await track.load(
                .timeRange, .preferredTransform, .naturalSize, .nominalFrameRate)
            let wanted = CMTimeRange(start: time(clip.start), end: time(clip.end))
            let range = wanted.intersection(trackRange)
            guard range.duration > .zero else { continue }
            try videoTrack.insertTimeRange(range, of: track, at: cursor)
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioRange = try await audio.load(.timeRange).intersection(range)
                if audioRange.duration > .zero {
                    try audioTrack.insertTimeRange(audioRange, of: audio, at: cursor + (audioRange.start - range.start))
                    hasAudio = true
                }
            }
            // Vitesse du clip, sur toutes les pistes.
            var duration = range.duration
            if clip.speed != 1 {
                let scaled = CMTimeMultiplyByFloat64(duration, multiplier: 1 / clip.speed)
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: duration), toDuration: scaled)
                duration = scaled
            }
            audioParameters.setVolume(plan.isMuted ? 0 : Float(clip.volume), at: cursor)
            let oriented = EditRendering.orientedSize(naturalSize, transform: transform)
            largestShortSide = max(largestShortSide, min(oriented.width, oriented.height))
            if pieces.isEmpty, nominalFrameRate > 0 { frameRate = min(nominalFrameRate.rounded(), maxFrameRate) }
            pieces.append(Piece(start: cursor, duration: duration, transform: transform, clip: clip))
            cursor = cursor + duration
        }
        if !hasAudio { composition.removeTrack(audioTrack) }
        guard !pieces.isEmpty, largestShortSide > 0 else { throw CocoaError(.fileReadCorruptFile) }

        let total = composition.duration
        let renderSize = renderSize(shortSide: largestShortSide)
        let overlay = includeTexts ? TextOverlayRenderer.image(plan.texts, stickers: plan.stickers, size: renderSize) : nil
        var instructions: [EditInstruction] = []
        for (index, piece) in pieces.enumerated() {
            // Bornes jointives : la dernière finit avec la composition.
            let end = index == pieces.count - 1 ? total : piece.end
            guard end > piece.start else { continue }
            instructions.append(
                EditInstruction(
                    timeRange: CMTimeRange(start: piece.start, end: end), trackID: videoTrack.trackID, transform: piece.transform,
                    quarterTurns: piece.clip.quarterTurns, crop: piece.clip.crop, renderSize: renderSize, filter: plan.filter,
                    filterIntensity: plan.filterIntensity, effects: plan.effects, overlay: overlay))
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = EditCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        videoComposition.instructions = instructions
        // Couleurs de la sortie : SDR BT.709 (une vidéo HDR est convertie par Core Image).
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        var audioMix: AVMutableAudioMix?
        if hasAudio {
            audioParameters.audioTimePitchAlgorithm = .spectral
            let mix = AVMutableAudioMix()
            mix.inputParameters = [audioParameters]
            audioMix = mix
        }
        return EditComposition(composition: composition, videoComposition: videoComposition, audioMix: audioMix, renderSize: renderSize)
    }

    // Image 9:16 dont le petit côté est celui du plus grand clip, ramené à 1080 px au plus, en dimensions paires.
    static func renderSize(shortSide: CGFloat) -> CGSize {
        let width = min(maxShortSide, shortSide)
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded() * 2) }
        return CGSize(width: even(width), height: even(width * 16 / 9))
    }

    private static func time(_ duration: Duration) -> CMTime {
        CMTime(seconds: duration.seconds, preferredTimescale: 600)
    }
}

// Instruction du compositeur : un segment de la vidéo finale, et comment rendre ses images.
final class EditInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    var timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?

    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let quarterTurns: Int
    let crop: CropRect
    let renderSize: CGSize
    let filter: VideoFilter
    let filterIntensity: Double
    // Plages d'effets, en temps de la vidéo finale (= temps de la composition).
    let effects: [TimedEffect]
    let overlay: CIImage?

    init(
        timeRange: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform, quarterTurns: Int, crop: CropRect,
        renderSize: CGSize, filter: VideoFilter, filterIntensity: Double = 1, effects: [TimedEffect] = [], overlay: CIImage?
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.transform = transform
        self.quarterTurns = quarterTurns
        self.crop = crop
        self.renderSize = renderSize
        self.filter = filter
        self.filterIntensity = filterIntensity
        self.effects = effects
        self.overlay = overlay
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

// Compositeur (Core Image) : rotation de la piste et du clip, cadre, image ajustée en 9:16, filtre, effets, textes et
// autocollants.
final class EditCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]
    ]
    // IOSurface : l'aperçu (`AVPlayerLayer`) ne sait afficher que des images partagées avec le GPU (sinon -12784).
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? EditInstruction, let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: CocoaError(.fileWriteUnknown))
            return
        }
        let bounds = CGRect(origin: .zero, size: instruction.renderSize)
        let image: CIImage
        if let frame = request.sourceFrame(byTrackID: instruction.trackID) {
            let seconds = request.compositionTime.seconds
            let effects = EffectTrack.active(instruction.effects, at: .seconds(seconds))
            image = EditRendering.render(
                CIImage(cvPixelBuffer: frame), transform: instruction.transform, quarterTurns: instruction.quarterTurns,
                crop: instruction.crop, renderSize: instruction.renderSize, filter: instruction.filter,
                filterIntensity: instruction.filterIntensity, effects: effects, time: seconds, overlay: instruction.overlay)
        } else {
            image = CIImage(color: .black).cropped(to: bounds)
        }
        context.render(image, to: output, bounds: bounds, colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
