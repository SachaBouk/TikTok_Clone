import AVFoundation
import CoreImage

// Composition AVFoundation d'un plan d'édition (ADR-052), partagée par l'aperçu de l'éditeur et l'export : même rendu.
// - fichiers d'origine mis bout à bout sur une piste vidéo et une piste son ;
// - intervalle gardé, puis vitesse (`scaleTimeRange`, sur toutes les pistes) ;
// - une instruction par fichier d'origine, pour le compositeur (`EditCompositor`) : rotation propre à chaque segment
//   (caméra avant ou arrière), filtre, textes.
struct EditComposition {
    // Petit côté de l'image exportée, au plus (jamais agrandie).
    static let maxShortSide: CGFloat = 1080
    static let maxFrameRate: Float = 60

    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let renderSize: CGSize

    private struct Piece {
        let start: CMTime
        let duration: CMTime
        let transform: CGAffineTransform
        var end: CMTime { start + duration }
    }

    // `includeTexts` faux pour l'aperçu : les textes y sont dessinés par SwiftUI, déplaçables au doigt.
    static func make(_ plan: EditPlan, includeTexts: Bool) async throws -> sending EditComposition {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.fileWriteUnknown) }

        var pieces: [Piece] = []
        var cursor = CMTime.zero
        var orientedSize = CGSize.zero
        var frameRate: Float = 30
        var hasAudio = false
        for clip in plan.clips {
            let asset = AVURLAsset(url: clip.file)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
            let (range, transform, naturalSize, nominalFrameRate) = try await track.load(
                .timeRange, .preferredTransform, .naturalSize, .nominalFrameRate)
            try videoTrack.insertTimeRange(range, of: track, at: cursor)
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioRange = try await audio.load(.timeRange).intersection(range)
                if audioRange.duration > .zero {
                    try audioTrack.insertTimeRange(audioRange, of: audio, at: cursor + (audioRange.start - range.start))
                    hasAudio = true
                }
            }
            if pieces.isEmpty {
                orientedSize = EditRendering.orientedSize(naturalSize, transform: transform)
                if nominalFrameRate > 0 { frameRate = min(nominalFrameRate.rounded(), maxFrameRate) }
            }
            pieces.append(Piece(start: cursor, duration: range.duration, transform: transform))
            cursor = cursor + range.duration
        }
        if !hasAudio { composition.removeTrack(audioTrack) }
        guard orientedSize.width > 0, orientedSize.height > 0 else { throw CocoaError(.fileReadCorruptFile) }

        // Intervalle gardé, dans la durée d'origine, puis vitesse.
        let start = min(CMTime(seconds: plan.trimStart.seconds, preferredTimescale: 600), cursor)
        let end = min(CMTime(seconds: plan.trimEnd.seconds, preferredTimescale: 600), cursor)
        if end < cursor { composition.removeTimeRange(CMTimeRange(start: end, end: cursor)) }
        if start > .zero { composition.removeTimeRange(CMTimeRange(start: .zero, end: start)) }
        let kept = end - start
        let factor = 1 / plan.speed.rawValue
        if plan.speed != .normal {
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: kept), toDuration: CMTimeMultiplyByFloat64(kept, multiplier: factor))
        }
        let total = composition.duration
        // Instant de la vidéo finale qui correspond à `time` dans la durée d'origine.
        func output(_ time: CMTime) -> CMTime {
            CMTimeMultiplyByFloat64(time - start, multiplier: factor)
        }

        let renderSize = renderSize(for: orientedSize)
        let overlay = includeTexts ? TextOverlayRenderer.image(plan.texts, size: renderSize) : nil
        let keptPieces = pieces.filter { $0.end > start && $0.start < end }
        var instructions: [EditInstruction] = []
        for (index, piece) in keptPieces.enumerated() {
            // Bornes jointives : la première commence à zéro, la dernière finit avec la composition.
            let from = index == 0 ? .zero : output(max(piece.start, start))
            let to = index == keptPieces.count - 1 ? total : output(min(piece.end, end))
            guard to > from else { continue }
            instructions.append(
                EditInstruction(
                    timeRange: CMTimeRange(start: from, end: to), trackID: videoTrack.trackID, transform: piece.transform,
                    renderSize: renderSize, filter: plan.filter, overlay: overlay))
        }
        if let last = instructions.last, last.timeRange.end != total {
            last.timeRange = CMTimeRange(start: last.timeRange.start, end: total)
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
        return EditComposition(composition: composition, videoComposition: videoComposition, renderSize: renderSize)
    }

    // Taille de l'image affichée, ramenée à un petit côté de 1080 px au plus, en dimensions paires.
    static func renderSize(for orientedSize: CGSize) -> CGSize {
        let scale = min(1, maxShortSide / min(orientedSize.width, orientedSize.height))
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(orientedSize.width), height: even(orientedSize.height))
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
    let renderSize: CGSize
    let filter: VideoFilter
    let overlay: CIImage?

    init(
        timeRange: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform, renderSize: CGSize, filter: VideoFilter,
        overlay: CIImage?
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.transform = transform
        self.renderSize = renderSize
        self.filter = filter
        self.overlay = overlay
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

// Compositeur (Core Image) : rotation du segment, remplissage de l'image finale, filtre, textes.
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
            image = EditRendering.render(
                CIImage(cvPixelBuffer: frame), transform: instruction.transform, renderSize: instruction.renderSize,
                filter: instruction.filter, overlay: instruction.overlay)
        } else {
            image = CIImage(color: .black).cropped(to: bounds)
        }
        context.render(image, to: output, bounds: bounds, colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
