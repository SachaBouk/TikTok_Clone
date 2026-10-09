import Foundation

// Port (ADR-002, ADR-053) : salle du serveur vidéo (LiveKit), pour diffuser sa caméra et son micro ou regarder. Le
// domaine ne connaît ni LiveKit ni WebRTC ; l'image est affichée par une vue fournie par l'adaptateur.

enum LiveRoomUpdate: Equatable, Sendable {
    // Événement diffusé par l'API (chat, cœurs, cadeaux, fin).
    case event(LiveRoomEvent)
    // Personnes dans la salle, l'auteur compris.
    case participants(Int)
    // Image de l'auteur disponible (spectateur) ou publiée (auteur).
    case videoAvailable(Bool)
    // Déconnecté (fin du live, réseau perdu, salle fermée).
    case disconnected
}

enum LiveRoomError: Error, Equatable, Sendable {
    // Pas de caméra (simulateur) ou caméra refusée : impossible de diffuser.
    case cameraUnavailable
    case connectionFailed
}

@MainActor
protocol LiveRoom: AnyObject {
    // Une seule séquence par salle : les mises à jour depuis la connexion.
    var updates: AsyncStream<LiveRoomUpdate> { get }
    // Se connecte ; `publish` : caméra (avant) et micro publiés. Lève LiveRoomError.
    func connect(url: URL, token: String, publish: Bool) async throws
    // Caméra avant ou arrière (auteur).
    func switchCamera() async
    func disconnect() async
}
