import AVFoundation

// Effets de voix (ADR-064) : la voix off passe hors temps réel dans une chaîne AVAudioEngine (hauteur, distorsion,
// égaliseur, réverbération, écho), écrite dans un nouveau fichier (gardé pendant la session de l'app, par voix et effet).
enum VoiceEffectRenderer {
    // Réglages d'un effet ; nil pour un maillon absent.
    struct Chain {
        var pitch: Float = 0
        var rate: Float = 1
        var distortion: AVAudioUnitDistortionPreset?
        var distortionMix: Float = 50
        var reverb: AVAudioUnitReverbPreset?
        var reverbMix: Float = 0
        // Égaliseur : passe-haut et passe-bas (Hz), et gain des aigus et des graves (dB).
        var highPass: Float?
        var lowPass: Float?
        var trebleGain: Float = 0
        var bassGain: Float = 0
        var delay: TimeInterval?
    }

    static func chain(for effect: VoiceEffect) -> Chain {
        switch effect {
        case .none: Chain()
        case .magnetic: Chain(distortion: .speechWaves, distortionMix: 40, reverb: .mediumRoom, reverbMix: 20)
        case .cave: Chain(reverb: .largeHall2, reverbMix: 60, delay: 0.25)
        case .church: Chain(reverb: .cathedral, reverbMix: 55)
        case .telephone: Chain(highPass: 400, lowPass: 3_400, trebleGain: 6)
        case .teenager: Chain(pitch: 300)
        case .phonograph: Chain(distortion: .drumsBitBrush, distortionMix: 25, highPass: 300, lowPass: 4_000)
        case .chipmunk: Chain(pitch: 900, rate: 1)
        case .giant: Chain(pitch: -700)
        case .robot: Chain(distortion: .speechCosmicInterference, distortionMix: 60)
        case .alien: Chain(pitch: 500, distortion: .speechAlienChatter, distortionMix: 50)
        case .clear: Chain(highPass: 90, trebleGain: 4)
        case .warm: Chain(trebleGain: -2, bassGain: 5)
        case .radio: Chain(distortion: .speechRadioTower, distortionMix: 45, highPass: 300, lowPass: 5_000)
        case .echo: Chain(reverb: .mediumHall, reverbMix: 25, delay: 0.35)
        }
    }

    // Fichier de la voix avec l'effet (CAF, PCM) ; la voix telle quelle sans effet.
    static func render(_ file: URL, effect: VoiceEffect) async throws -> URL {
        guard effect != .none else { return file }
        let directory = URL.temporaryDirectory.appending(path: "VoiceEffects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: "\(file.deletingPathExtension().lastPathComponent)-\(effect.rawValue).caf")
        if FileManager.default.fileExists(atPath: output.path()) { return output }
        try await Task.detached(priority: .userInitiated) {
            try renderOffline(file, chain: chain(for: effect), to: output)
        }.value
        return output
    }

    private static func renderOffline(_ input: URL, chain: Chain, to output: URL) throws {
        let source = try AVAudioFile(forReading: input)
        let format = source.processingFormat
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        var nodes: [AVAudioNode] = []
        if chain.pitch != 0 || chain.rate != 1 {
            let pitch = AVAudioUnitTimePitch()
            pitch.pitch = chain.pitch
            pitch.rate = chain.rate
            nodes.append(pitch)
        }
        if chain.highPass != nil || chain.lowPass != nil || chain.trebleGain != 0 || chain.bassGain != 0 {
            let eq = AVAudioUnitEQ(numberOfBands: 4)
            configure(eq.bands[0], type: .highPass, frequency: chain.highPass, gain: 0)
            configure(eq.bands[1], type: .lowPass, frequency: chain.lowPass, gain: 0)
            configure(eq.bands[2], type: .highShelf, frequency: chain.trebleGain != 0 ? 3_000 : nil, gain: chain.trebleGain)
            configure(eq.bands[3], type: .lowShelf, frequency: chain.bassGain != 0 ? 200 : nil, gain: chain.bassGain)
            nodes.append(eq)
        }
        if let preset = chain.distortion {
            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(preset)
            distortion.wetDryMix = chain.distortionMix
            nodes.append(distortion)
        }
        if let delayTime = chain.delay {
            let delay = AVAudioUnitDelay()
            delay.delayTime = delayTime
            delay.feedback = 30
            delay.wetDryMix = 30
            nodes.append(delay)
        }
        if let preset = chain.reverb {
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(preset)
            reverb.wetDryMix = chain.reverbMix
            nodes.append(reverb)
        }
        var previous: AVAudioNode = player
        for node in nodes {
            engine.attach(node)
            engine.connect(previous, to: node, format: format)
            previous = node
        }
        engine.connect(previous, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        try engine.start()
        player.scheduleFile(source, at: nil)
        player.play()

        let target = try AVAudioFile(forWriting: output, settings: engine.manualRenderingFormat.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)
        else { throw CocoaError(.fileWriteUnknown) }
        // Queue de réverbération et d'écho : une seconde de plus, coupée à l'export à la durée de la voix.
        let total = source.length + AVAudioFramePosition(format.sampleRate)
        while engine.manualRenderingSampleTime < total {
            let frames = AVAudioFrameCount(min(Int64(buffer.frameCapacity), total - engine.manualRenderingSampleTime))
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success: try target.write(from: buffer)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext: continue
            case .error: throw CocoaError(.fileWriteUnknown)
            @unknown default: throw CocoaError(.fileWriteUnknown)
            }
        }
        player.stop()
        engine.stop()
    }

    private static func configure(_ band: AVAudioUnitEQFilterParameters, type: AVAudioUnitEQFilterType, frequency: Float?, gain: Float) {
        guard let frequency else {
            band.bypass = true
            return
        }
        band.filterType = type
        band.frequency = frequency
        band.gain = gain
        band.bandwidth = 1
        band.bypass = false
    }
}
