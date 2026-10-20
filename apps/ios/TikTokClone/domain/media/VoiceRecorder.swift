import Foundation

// Port (ADR-064) : micro de l'iPhone, pour enregistrer une voix off. L'implémentation (data/media) s'appuie sur
// AVAudioRecorder.
@MainActor
protocol VoiceRecorder: AnyObject {
    // Autorisation du micro, demandée au besoin.
    func requestPermission() async -> Bool
    // Enregistre dans un nouveau fichier jusqu'à `stop()` ; faux si l'enregistrement ne démarre pas.
    func start() -> Bool
    // Fichier enregistré et sa durée ; nil si rien n'a été enregistré.
    func stop() -> (file: URL, duration: Duration)?
}
