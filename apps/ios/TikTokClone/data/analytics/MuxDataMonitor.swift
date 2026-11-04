import AVFoundation
import MUXSDKStats
import MuxCore

// Mux Data (ADR-074) : démarrage, coupures et qualité de chaque lecture, envoyés à Mux avec la clé d'environnement
// (`MUX_DATA_ENV_KEY`). Seulement avec le consentement à la mesure d'audience (ADR-024) : rien n'est suivi sans lui, et un
// retrait arrête tout. Aucun identifiant de compte n'est envoyé.
@MainActor
final class MuxDataMonitor: PlaybackMonitor {
    // Taille d'affichage annoncée : les lecteurs de l'app occupent l'écran, en vertical.
    static let playerSize = CGSize(width: 1080, height: 1920)

    private let environmentKey: String
    private var enabled = false
    // Lecteur suivi → nom donné à Mux Data.
    private var names: [ObjectIdentifier: String] = [:]

    init(environmentKey: String) {
        self.environmentKey = environmentKey
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        guard !enabled else { return }
        for name in names.values { MUXSDKStats.destroyPlayer(name) }
        names = [:]
    }

    func start(_ player: AVPlayer, video: MonitoredVideo) {
        guard enabled, names[ObjectIdentifier(player)] == nil else { return }
        guard let playerData = MUXSDKCustomerPlayerData(environmentKey: environmentKey) else { return }
        playerData.playerName = "TikTok Clone"
        let videoData = MUXSDKCustomerVideoData()
        videoData.videoId = video.id
        videoData.videoCdn = video.cdn
        videoData.videoStreamType = "on-demand"
        guard let customerData = MUXSDKCustomerData(customerPlayerData: playerData, videoData: videoData, viewData: nil, customData: nil) else {
            return
        }
        let name = "player-\(UUID().uuidString)"
        names[ObjectIdentifier(player)] = name
        MUXSDKStats.monitorAVPlayer(player, withPlayerName: name, fixedPlayerSize: Self.playerSize, customerData: customerData)
    }

    func stop(_ player: AVPlayer) {
        guard let name = names.removeValue(forKey: ObjectIdentifier(player)) else { return }
        MUXSDKStats.destroyPlayer(name)
    }
}
