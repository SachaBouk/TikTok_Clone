import AVFoundation

// Sons de l'interface joués par un `AVAudioEngine` (ADR-075) : échantillons calculés par `ToneSynth` au premier usage,
// quatre lecteurs utilisés à tour de rôle (sons superposés). Session `.ambient` le temps de l'onboarding : les sons
// respectent le mode silencieux et se mêlent à la musique en cours ; la session des vidéos (`.playback`) revient ensuite.
@MainActor
final class SynthesizedSoundPlayer: UISoundPlayer {
    private let engine = AVAudioEngine()
    private let players = (0..<4).map { _ in AVAudioPlayerNode() }
    private let format = AVAudioFormat(standardFormatWithSampleRate: ToneSynth.sampleRate, channels: 1)
    private var buffers: [UISound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var activations = 0

    init() {
        guard let format else { return }
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
    }

    func activate() {
        activations += 1
        guard activations == 1 else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngine()
    }

    func deactivate() {
        guard activations > 0 else { return }
        activations -= 1
        guard activations == 0 else { return }
        for player in players { player.stop() }
        engine.stop()
        // Session des vidéos (ADR-002) : le son joue même en mode silencieux.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    func play(_ sound: UISound) {
        guard activations > 0, let buffer = buffer(for: sound) else { return }
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    private func startEngine() {
        do {
            try engine.start()
        } catch {
            // Pas de son (simulateur sans sortie audio, session refusée) : l'onboarding continue sans.
        }
    }

    private func buffer(for sound: UISound) -> AVAudioPCMBuffer? {
        if let buffer = buffers[sound] { return buffer }
        let samples = ToneSynth.samples(for: sound)
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffers[sound] = buffer
        return buffer
    }
}
