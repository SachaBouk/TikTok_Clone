import Foundation

// Port (ADR-002, ADR-052) : caméra de l'iPhone, pour filmer des segments ou prendre une photo de story.
// L'implémentation (data/camera) s'appuie sur AVCaptureSession ; le simulateur n'a pas de caméra.

enum CameraPosition: Equatable, Sendable {
    case back
    case front

    var toggled: CameraPosition { self == .back ? .front : .back }
}

// Résultat du démarrage de la caméra.
enum CameraStart: Equatable, Sendable {
    // `hasAudio` faux : micro refusé, les segments sont filmés sans son.
    case ready(hasAudio: Bool)
    case denied
    case unavailable
}

@MainActor
protocol VideoCamera: AnyObject {
    // Autorisations demandées au besoin, puis aperçu démarré.
    func start(position: CameraPosition) async -> CameraStart
    func stop()
    // Faux si cette caméra n'existe pas sur l'appareil.
    func switchTo(_ position: CameraPosition) async -> Bool
    // Lampe : caméra arrière seulement.
    var hasTorch: Bool { get }
    func setTorch(_ on: Bool)
    // Filme un segment, jusqu'à `stopRecording()` ou `maxDuration` ; `onFinish` reçoit le fichier filmé.
    func startRecording(maxDuration: Duration, onFinish: @escaping @MainActor (Result<SourceClip, any Error>) -> Void)
    func stopRecording()
    // Photo d'une story : données de l'image, préparées ensuite comme une photo de la galerie.
    func capturePhoto() async throws -> Data
}
