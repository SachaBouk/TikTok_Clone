import AVFoundation

// Voix off (ADR-064) : AVAudioRecorder, AAC mono 44,1 kHz, dans le dossier temporaire. Pendant l'enregistrement, la
// session audio passe en lecture et enregistrement (haut-parleur), puis revient en lecture seule.
@MainActor
final class AVFoundationVoiceRecorder: VoiceRecorder {
    private var recorder: AVAudioRecorder?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() -> Bool {
        let directory = URL.temporaryDirectory.appending(path: "Voiceovers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            guard recorder.record() else { return false }
            self.recorder = recorder
            return true
        } catch {
            restorePlayback()
            return false
        }
    }

    func stop() -> (file: URL, duration: Duration)? {
        guard let recorder else { return nil }
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        restorePlayback()
        guard seconds > 0 else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return (recorder.url, .seconds(seconds))
    }

    private func restorePlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
}
