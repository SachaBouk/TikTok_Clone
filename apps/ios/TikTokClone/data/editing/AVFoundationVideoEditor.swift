import AVFoundation
import UIKit

// Export d'une vidéo modifiée, sur l'iPhone (ADR-052) :
// - sans réencodage quand un seul fichier d'origine est seulement découpé (préréglage `Passthrough`) : qualité et
//   couleurs HDR d'origine gardées, comme la préparation d'une vidéo de la galerie (ADR-035) ;
// - sinon, réencodage en H.264 par la composition et son compositeur (`EditComposition`), hauteur du son gardée
//   malgré la vitesse (`spectral`).
// Toujours en QuickTime (.mov), avec le filtre de partage : ni position GPS, ni appareil (ADR-035).
struct AVFoundationVideoEditor: VideoEditor {
    func export(_ plan: EditPlan) async throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "Edited", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: "\(UUID().uuidString).mov")

        let session: AVAssetExportSession
        if !plan.needsReencoding, let clip = plan.clips.first {
            guard let passthrough = AVAssetExportSession(asset: AVURLAsset(url: clip.file), presetName: AVAssetExportPresetPassthrough) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if plan.isTrimmed {
                passthrough.timeRange = CMTimeRange(
                    start: CMTime(seconds: plan.trimStart.seconds, preferredTimescale: 600),
                    end: CMTime(seconds: plan.trimEnd.seconds, preferredTimescale: 600))
            }
            session = passthrough
        } else {
            let built = try await EditComposition.make(plan, includeTexts: true)
            guard let reencode = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw CocoaError(.fileWriteUnknown)
            }
            reencode.videoComposition = built.videoComposition
            reencode.audioTimePitchAlgorithm = .spectral
            session = reencode
        }
        session.metadataItemFilter = .forSharing()
        do {
            try await session.export(to: output, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }
}

// Miniatures de la frise de découpage : réparties sur la durée d'origine (tous segments), rotation appliquée.
enum EditThumbnails {
    static func images(for plan: EditPlan, count: Int, maxSize: CGSize = CGSize(width: 160, height: 160)) async -> [UIImage] {
        guard count > 0, plan.sourceDuration > .zero else { return [] }
        var images: [UIImage] = []
        var generators: [URL: AVAssetImageGenerator] = [:]
        for index in 0..<count {
            let time = plan.sourceDuration * ((Double(index) + 0.5) / Double(count))
            guard let (clip, local) = plan.clipPosition(at: time) else { continue }
            let generator =
                generators[clip.file]
                ?? {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.file))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = maxSize
                    generator.requestedTimeToleranceBefore = .positiveInfinity
                    generator.requestedTimeToleranceAfter = .positiveInfinity
                    return generator
                }()
            generators[clip.file] = generator
            if let (image, _) = try? await generator.image(at: CMTime(seconds: local.seconds, preferredTimescale: 600)) {
                images.append(UIImage(cgImage: image))
            }
        }
        return images
    }
}

// Aperçu de l'éditeur : la composition du plan avec le même compositeur que l'export (sans les textes, dessinés par
// SwiftUI), lue en boucle par un `AVPlayer` qui revient au début à la fin (`AVPlayerLooper` ne gardait pas l'élément).
// Si le lecteur refuse la composition vidéo (simulateur : aucune composition n'y est affichée par un `AVPlayerLayer`,
// erreur -12784), l'aperçu se relit sans elle : découpage, vitesse et son, mais ni filtre ni rotation (`isSimplified`).
@MainActor
@Observable
final class EditorPreviewPlayer {
    let player = AVPlayer()
    // Proportions de l'image finale (largeur / hauteur) ; 9:16 en attendant la première composition.
    private(set) var aspectRatio: CGFloat = 9.0 / 16.0
    private(set) var failed = false
    private(set) var isSimplified = false
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    // Composition lue, pour la relire sans composition vidéo si le lecteur la refuse.
    @ObservationIgnored private var composition: AVComposition?

    init() {
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = true
    }

    func load(_ plan: EditPlan) async {
        // Aperçu même d'une vidéo encore trop longue : on y choisit le passage à garder.
        guard !plan.clips.isEmpty else { return }
        do {
            let built = try await EditComposition.make(plan, includeTexts: false)
            guard !Task.isCancelled else { return }
            aspectRatio = built.renderSize.width / built.renderSize.height
            failed = false
            play(built.composition, videoComposition: isSimplified ? nil : built.videoComposition)
        } catch {
            failed = true
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func stop() {
        player.pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
    }

    private func play(_ composition: AVComposition, videoComposition: AVVideoComposition?) {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioTimePitchAlgorithm = .spectral
        removeObservers()
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }
        self.composition = composition
        if videoComposition != nil {
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in self?.simplify() }
            }
        }
        player.play()
    }

    private func simplify() {
        guard player.currentItem?.status == .failed, player.currentItem?.videoComposition != nil, let composition else { return }
        isSimplified = true
        play(composition, videoComposition: nil)
    }

    private func removeObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
    }
}
