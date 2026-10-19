import AVFoundation
import UIKit

// Export d'une vidéo modifiée, sur l'iPhone (ADR-052, ADR-062) :
// - sans réencodage quand un seul clip est seulement découpé (préréglage `Passthrough`) : qualité, format et couleurs
//   HDR d'origine gardés, comme la préparation d'une vidéo de la galerie (ADR-035) ;
// - sinon, réencodage en H.264 par la composition et son compositeur (`EditComposition`, image en 9:16), volume de
//   chaque clip, hauteur du son gardée malgré la vitesse (`spectral`).
// Toujours en QuickTime (.mov), avec le filtre de partage : ni position GPS, ni appareil (ADR-035).
struct AVFoundationVideoEditor: VideoEditor {
    func export(_ plan: EditPlan) async throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "Edited", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: "\(UUID().uuidString).mov")

        let session: AVAssetExportSession
        if !plan.needsReencoding, let clip = plan.clips.first {
            guard let passthrough = AVAssetExportSession(asset: AVURLAsset(url: clip.source.file), presetName: AVAssetExportPresetPassthrough)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if clip.isTrimmed {
                passthrough.timeRange = CMTimeRange(
                    start: CMTime(seconds: clip.start.seconds, preferredTimescale: 600),
                    end: CMTime(seconds: clip.end.seconds, preferredTimescale: 600))
            }
            session = passthrough
        } else {
            let built = try await EditComposition.make(plan, includeTexts: true)
            guard let reencode = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw CocoaError(.fileWriteUnknown)
            }
            reencode.videoComposition = built.videoComposition
            reencode.audioMix = built.audioMix
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

// Miniatures de la frise : images d'un fichier d'origine aux instants donnés, rotation de la piste appliquée.
enum EditThumbnails {
    // `exact` : l'image à l'instant demandé (recadrage), sinon l'image clé la plus proche (frise, plus rapide).
    static func images(
        of source: SourceClip, at times: [Duration], maxSize: CGSize = CGSize(width: 160, height: 160), exact: Bool = false
    ) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source.file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = exact ? .zero : .positiveInfinity
        generator.requestedTimeToleranceAfter = exact ? .zero : .positiveInfinity
        var images: [UIImage] = []
        for time in times {
            if let (image, _) = try? await generator.image(at: CMTime(seconds: time.seconds, preferredTimescale: 600)) {
                images.append(UIImage(cgImage: image))
            }
        }
        return images
    }
}

// Aperçu de l'éditeur : la composition du plan avec le même compositeur que l'export (sans les textes, dessinés par
// SwiftUI). En boucle sur l'écran d'aperçu ; dans l'éditeur par clips, lecture jusqu'à la fin, position suivie
// (`currentTime`) et réglée par la frise (`seek`). Si le lecteur refuse la composition vidéo (simulateur : aucune
// composition n'y est affichée par un `AVPlayerLayer`, erreur -12784), l'aperçu se relit sans elle : découpage, vitesse
// et son, mais ni filtre, ni rotation, ni cadre (`isSimplified`).
@MainActor
@Observable
final class EditorPreviewPlayer {
    let player = AVPlayer()
    // Proportions de l'image finale (largeur / hauteur) : 9:16 (ADR-062).
    private(set) var aspectRatio: CGFloat = 9.0 / 16.0
    private(set) var failed = false
    private(set) var isSimplified = false
    private(set) var isPlaying = false
    private(set) var currentTime: Duration = .zero
    private(set) var duration: Duration = .zero
    // Faux dans l'éditeur par clips : la lecture s'arrête à la fin.
    var loops = true
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    // Composition lue, pour la relire sans composition vidéo si le lecteur la refuse.
    @ObservationIgnored private var composition: AVComposition?
    @ObservationIgnored private var audioMix: AVAudioMix?

    init() {
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.isNumeric else { return }
                self.currentTime = .milliseconds(Int64(time.seconds * 1000))
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    // `autoplay` faux : la composition est prête, à l'instant `at`, sans lecture.
    func load(_ plan: EditPlan, at time: Duration? = nil, autoplay: Bool = true) async {
        guard !plan.clips.isEmpty else { return }
        do {
            let built = try await EditComposition.make(plan, includeTexts: false)
            guard !Task.isCancelled else { return }
            aspectRatio = built.renderSize.width / built.renderSize.height
            failed = false
            duration = plan.outputDuration
            play(built.composition, videoComposition: isSimplified ? nil : built.videoComposition, audioMix: built.audioMix)
            if let time { seek(to: min(time, plan.outputDuration)) }
            if autoplay { player.play() } else { player.pause() }
            isPlaying = autoplay
        } catch {
            failed = true
        }
    }

    func play() {
        // Arrivé au bout : repart du début.
        if !loops, currentTime >= duration - .milliseconds(50) { seek(to: .zero) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    // Image exacte : la frise suit la tête de lecture.
    func seek(to time: Duration) {
        let target = CMTime(seconds: max(0, time.seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(.zero, time)
    }

    func stop() {
        pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
    }

    private func play(_ composition: AVComposition, videoComposition: AVVideoComposition?, audioMix: AVAudioMix?) {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        item.audioTimePitchAlgorithm = .spectral
        removeObservers()
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.loops {
                    self.player.seek(to: .zero)
                    self.player.play()
                } else {
                    self.isPlaying = false
                }
            }
        }
        self.composition = composition
        self.audioMix = audioMix
        if videoComposition != nil {
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in self?.simplify() }
            }
        }
    }

    private func simplify() {
        guard player.currentItem?.status == .failed, player.currentItem?.videoComposition != nil, let composition else { return }
        isSimplified = true
        let time = currentTime
        play(composition, videoComposition: nil, audioMix: audioMix)
        seek(to: time)
        if isPlaying { player.play() }
    }

    private func removeObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
    }
}
