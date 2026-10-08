import AVFoundation
import UIKit

// Caméra de l'iPhone (ADR-052) : `AVCaptureSession` en 1080p, portrait, segments filmés par `AVCaptureMovieFileOutput`
// (son compris si le micro est autorisé), photos de story par `AVCapturePhotoOutput`. Toute la configuration passe par
// une file série dédiée (`startRunning` bloque). Le simulateur n'a pas de caméra : `start` renvoie `.unavailable`.
// Les métadonnées des fichiers filmés (appareil, date) sont retirées à l'export (ADR-035).
@MainActor
final class AVFoundationVideoCamera: VideoCamera {
    // Graphe de capture, manipulé seulement sur `queue`.
    final class Graph: @unchecked Sendable {
        let session = AVCaptureSession()
        let movieOutput = AVCaptureMovieFileOutput()
        let photoOutput = AVCapturePhotoOutput()
        var videoInput: AVCaptureDeviceInput?
        var configured = false
    }

    nonisolated let graph = Graph()
    private nonisolated let queue = DispatchQueue(label: "com.sachabouk.tiktokclone.camera")
    private var position: CameraPosition = .back
    private var recordingDelegate: RecordingDelegate?
    private var photoDelegate: PhotoDelegate?

    // Pour l'aperçu (`CameraPreview`).
    nonisolated var session: AVCaptureSession { graph.session }

    var hasTorch: Bool {
        position == .back && Self.device(for: .back)?.hasTorch == true
    }

    func start(position: CameraPosition) async -> CameraStart {
        guard Self.device(for: position) ?? Self.device(for: position.toggled) != nil else { return .unavailable }
        guard await Self.authorize(.video) else { return .denied }
        let hasAudio = await Self.authorize(.audio)
        let wanted = Self.device(for: position) != nil ? position : position.toggled
        let ok = await perform { graph in
            if !graph.configured {
                guard Self.configure(graph, position: wanted, audio: hasAudio) else { return false }
                graph.configured = true
            }
            if !graph.session.isRunning { graph.session.startRunning() }
            return true
        }
        guard ok else { return .unavailable }
        self.position = wanted
        return .ready(hasAudio: hasAudio)
    }

    func stop() {
        queue.async { [graph] in
            if graph.movieOutput.isRecording { graph.movieOutput.stopRecording() }
            if graph.session.isRunning { graph.session.stopRunning() }
        }
    }

    func switchTo(_ position: CameraPosition) async -> Bool {
        let switched = await perform { graph in
            guard let device = Self.device(for: position), let input = try? AVCaptureDeviceInput(device: device) else { return false }
            graph.session.beginConfiguration()
            defer { graph.session.commitConfiguration() }
            if let current = graph.videoInput { graph.session.removeInput(current) }
            guard graph.session.canAddInput(input) else {
                if let current = graph.videoInput { graph.session.addInput(current) }
                return false
            }
            graph.session.addInput(input)
            graph.videoInput = input
            Self.orientConnections(graph, mirrored: position == .front)
            return true
        }
        if switched { self.position = position }
        return switched
    }

    func setTorch(_ on: Bool) {
        guard hasTorch else { return }
        queue.async {
            guard let device = Self.device(for: .back), (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    func startRecording(maxDuration: Duration, onFinish: @escaping @MainActor (Result<SourceClip, any Error>) -> Void) {
        let directory = URL.temporaryDirectory.appending(path: "Recorded", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(UUID().uuidString).mov")
        let delegate = RecordingDelegate { url, error in
            Task { @MainActor in
                if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                    try? FileManager.default.removeItem(at: url)
                    onFinish(.failure(error))
                    return
                }
                let duration = (try? await AVURLAsset(url: url).load(.duration)).map { Duration.seconds($0.seconds) } ?? .zero
                onFinish(.success(SourceClip(file: url, duration: duration)))
            }
        }
        recordingDelegate = delegate
        queue.async { [graph] in
            graph.movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration.seconds, preferredTimescale: 600)
            graph.movieOutput.startRecording(to: file, recordingDelegate: delegate)
        }
    }

    func stopRecording() {
        queue.async { [graph] in
            if graph.movieOutput.isRecording { graph.movieOutput.stopRecording() }
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoDelegate { result in continuation.resume(with: result) }
            photoDelegate = delegate
            queue.async { [graph] in
                graph.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }

    // Sur `queue`.
    private func perform<T: Sendable>(_ work: @escaping @Sendable (Graph) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { [graph] in continuation.resume(returning: work(graph)) }
        }
    }

    private nonisolated static func configure(_ graph: Graph, position: CameraPosition, audio: Bool) -> Bool {
        let session = graph.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        guard let device = device(for: position), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        graph.videoInput = input
        if audio, let microphone = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: microphone),
            session.canAddInput(audioInput)
        {
            session.addInput(audioInput)
        }
        guard session.canAddOutput(graph.movieOutput), session.canAddOutput(graph.photoOutput) else { return false }
        session.addOutput(graph.movieOutput)
        session.addOutput(graph.photoOutput)
        orientConnections(graph, mirrored: position == .front)
        return true
    }

    // Portrait (quart de tour), caméra avant en miroir, comme l'aperçu.
    private nonisolated static func orientConnections(_ graph: Graph, mirrored: Bool) {
        for connection in [graph.movieOutput.connection(with: .video), graph.photoOutput.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
    }

    private nonisolated static func device(for position: CameraPosition) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position == .front ? .front : .back)
    }

    private nonisolated static func authorize(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: media)
        default: false
        }
    }
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, Sendable {
    let finished: @Sendable (URL, (any Error)?) -> Void

    init(finished: @escaping @Sendable (URL, (any Error)?) -> Void) {
        self.finished = finished
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?
    ) {
        finished(outputFileURL, error)
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    let finished: @Sendable (Result<Data, any Error>) -> Void

    init(finished: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        self.finished = finished
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            finished(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            finished(.success(data))
        } else {
            finished(.failure(CocoaError(.fileReadCorruptFile)))
        }
    }
}
