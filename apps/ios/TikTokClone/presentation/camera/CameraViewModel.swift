import Foundation
import Observation

// Caméra de l'onglet « Publier » (ADR-052) : segments filmés (toucher pour démarrer, toucher pour arrêter), caméra avant
// ou arrière entre deux segments, lampe, minuteur de 3 s ; en mode Story, une photo. La durée totale est bornée par la
// publication (3 minutes, ou 60 s pour une story) : l'enregistrement s'arrête seul à la limite.
@MainActor
@Observable
final class CameraViewModel {
    enum Status: Equatable {
        case starting
        case ready
        case denied
        case unavailable
    }

    enum CaptureMode: String, CaseIterable, Identifiable {
        case video
        case photo

        var id: String { rawValue }
        var title: String { self == .video ? "Vidéo" : "Photo" }
    }

    static let countdownSeconds = 3

    let kind: PublicationKind
    private(set) var status: Status = .starting
    private(set) var recording: RecordingSession
    private(set) var isRecording = false
    // Début du segment en cours : la barre de progression avance avec l'horloge.
    private(set) var recordingStartedAt: Date?
    private(set) var countdown: Int?
    private(set) var position: CameraPosition = .back
    private(set) var torchOn = false
    // Micro refusé : les segments sont filmés sans son.
    private(set) var hasAudio = true
    private(set) var isCapturingPhoto = false
    var timerEnabled = false
    var captureMode: CaptureMode = .video
    var errorMessage: String?

    private let camera: any VideoCamera
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private var countdownTask: Task<Void, Never>?

    init(
        kind: PublicationKind, camera: any VideoCamera,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.kind = kind
        self.camera = camera
        self.sleep = sleep
        self.now = now
        recording = RecordingSession(kind: kind)
    }

    // Photo : stories seulement (ADR-051).
    var captureModes: [CaptureMode] { kind == .story ? CaptureMode.allCases : [.video] }

    var isBusy: Bool { isRecording || countdown != nil || isCapturingPhoto }
    var canSwitchCamera: Bool { status == .ready && !isBusy }
    var canUseTorch: Bool { status == .ready && position == .back && camera.hasTorch }
    var canRecord: Bool { status == .ready && !recording.isFull && !isCapturingPhoto }
    var canRemoveLast: Bool { !recording.segments.isEmpty && !isBusy }
    var canFinish: Bool { !recording.segments.isEmpty && !isBusy }
    var hasSegments: Bool { !recording.segments.isEmpty }

    func start() async {
        switch await camera.start(position: position) {
        case .ready(let hasAudio):
            self.hasAudio = hasAudio
            status = .ready
        case .denied:
            status = .denied
        case .unavailable:
            status = .unavailable
        }
    }

    // Écran fermé ou app en arrière-plan : le segment en cours se termine (il est gardé).
    func stop() {
        cancelCountdown()
        if isRecording { camera.stopRecording() }
        if torchOn {
            torchOn = false
            camera.setTorch(false)
        }
        camera.stop()
    }

    func switchCamera() async {
        guard canSwitchCamera else { return }
        let target = position.toggled
        if await camera.switchTo(target) {
            position = target
            torchOn = false
        }
    }

    func toggleTorch() {
        guard canUseTorch else { return }
        torchOn.toggle()
        camera.setTorch(torchOn)
    }

    // Déclencheur en mode vidéo : démarre (après le minuteur s'il est activé) ou arrête un segment ; pendant le
    // minuteur, l'annule.
    func shutterTapped() {
        if countdown != nil {
            cancelCountdown()
            return
        }
        if isRecording {
            camera.stopRecording()
            return
        }
        guard canRecord else { return }
        guard timerEnabled else {
            beginRecording()
            return
        }
        // Posé tout de suite : un second toucher, même immédiat, annule le minuteur.
        countdown = Self.countdownSeconds
        countdownTask = Task { [weak self, sleep] in
            for remaining in stride(from: Self.countdownSeconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                self?.countdown = remaining
                do { try await sleep(.seconds(1)) } catch { return }
            }
            if Task.isCancelled { return }
            self?.countdown = nil
            self?.beginRecording()
        }
    }

    // Attendu par les tests.
    func waitForCountdown() async {
        await countdownTask?.value
    }

    // Part de la durée maximale filmée, segment en cours compris.
    func progress(at date: Date) -> Double {
        let current = recordingStartedAt.map { Duration.seconds(max(0, date.timeIntervalSince($0))) } ?? .zero
        return recording.progress(including: current)
    }

    func removeLastSegment() {
        guard canRemoveLast, let segment = recording.removeLast() else { return }
        try? FileManager.default.removeItem(at: segment.file)
    }

    // « Suivant » : les segments passent à l'éditeur, qui en devient responsable (fichiers compris).
    func finishRecording() -> [SourceClip]? {
        guard canFinish else { return nil }
        stop()
        return recording.removeAll()
    }

    // Photo de story : ses données, préparées ensuite comme une photo de la galerie.
    func takePhoto() async -> Data? {
        guard status == .ready, !isBusy else { return nil }
        isCapturingPhoto = true
        defer { isCapturingPhoto = false }
        do {
            return try await camera.capturePhoto()
        } catch {
            errorMessage = "Impossible de prendre la photo."
            return nil
        }
    }

    // Abandon : la caméra s'arrête, les segments filmés sont supprimés.
    func discard() {
        stop()
        for segment in recording.removeAll() {
            try? FileManager.default.removeItem(at: segment.file)
        }
    }

    private func beginRecording() {
        guard canRecord else { return }
        isRecording = true
        recordingStartedAt = now()
        camera.startRecording(maxDuration: recording.remaining) { [weak self] result in
            self?.recordingFinished(result)
        }
    }

    private func recordingFinished(_ result: Result<SourceClip, any Error>) {
        isRecording = false
        recordingStartedAt = nil
        switch result {
        case .success(let segment):
            // Toucher trop bref : le segment est ignoré.
            if !recording.append(segment) { try? FileManager.default.removeItem(at: segment.file) }
        case .failure:
            errorMessage = "L’enregistrement a échoué."
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }
}
