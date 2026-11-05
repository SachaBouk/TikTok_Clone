import Foundation

// Synthèse des sons de l'interface (ADR-075) : formes d'onde calculées (sinus, triangle, bruit filtré) avec une
// enveloppe, en mono. Sons originaux, sans fichier ni droits d'auteur. Fonctions pures, testées.
enum ToneSynth {
    static let sampleRate = 44_100.0

    // Une note : fréquence de départ et d'arrivée (glissando), début et durée en secondes, volume.
    struct Note {
        var from: Double
        var to: Double
        var start: Double
        var duration: Double
        var volume: Double = 0.5
        var wave: Wave = .sine
        // Attaque et fin de l'enveloppe, en secondes.
        var attack = 0.004
        var release = 0.06
    }

    enum Wave {
        case sine, triangle
        // Bruit blanc filtré (passe-bas qui s'ouvre puis se referme) : souffle.
        case noise
    }

    static func notes(for sound: UISound) -> [Note] {
        // Gamme de do majeur (une octave haute) : C6 1047, E6 1319, G6 1568, C7 2093.
        switch sound {
        case .tap:
            return [Note(from: 900, to: 620, start: 0, duration: 0.05, volume: 0.35, release: 0.04)]
        case .select:
            return [
                Note(from: 1047, to: 1047, start: 0, duration: 0.06, volume: 0.32, release: 0.05),
                Note(from: 1568, to: 1568, start: 0.055, duration: 0.09, volume: 0.32, release: 0.08),
            ]
        case .toggle:
            return [Note(from: 1319, to: 1568, start: 0, duration: 0.06, volume: 0.28, wave: .triangle, release: 0.05)]
        case .whoosh:
            return [Note(from: 400, to: 2_400, start: 0, duration: 0.28, volume: 0.22, wave: .noise, attack: 0.08, release: 0.16)]
        case .pop:
            return [Note(from: 320, to: 980, start: 0, duration: 0.09, volume: 0.45, release: 0.06)]
        case .speedUp:
            return [Note(from: 440, to: 1_760, start: 0, duration: 0.35, volume: 0.25, wave: .triangle, attack: 0.02, release: 0.1)]
        case .tick:
            return [Note(from: 2_093, to: 2_093, start: 0, duration: 0.025, volume: 0.22, release: 0.02)]
        case .success:
            return [
                Note(from: 1047, to: 1047, start: 0, duration: 0.12, volume: 0.28, release: 0.1),
                Note(from: 1319, to: 1319, start: 0.07, duration: 0.14, volume: 0.28, release: 0.12),
                Note(from: 1568, to: 1568, start: 0.14, duration: 0.3, volume: 0.3, release: 0.25),
            ]
        case .celebrate:
            let arpeggio = [523.0, 659, 784, 1047, 1319, 1568, 2093].enumerated().map { index, frequency in
                Note(from: frequency, to: frequency, start: Double(index) * 0.065, duration: 0.16, volume: 0.26, wave: .triangle, release: 0.12)
            }
            let sparkle = (0..<6).map { index in
                Note(from: 3_136, to: 3_520, start: 0.45 + Double(index) * 0.05, duration: 0.05, volume: 0.08, release: 0.04)
            }
            let chord = [1047.0, 1319, 1568].map { Note(from: $0, to: $0, start: 0.46, duration: 0.55, volume: 0.16, release: 0.45) }
            return arpeggio + sparkle + chord
        case .error:
            return [
                Note(from: 392, to: 392, start: 0, duration: 0.1, volume: 0.3, wave: .triangle, release: 0.06),
                Note(from: 311, to: 294, start: 0.1, duration: 0.18, volume: 0.3, wave: .triangle, release: 0.12),
            ]
        case .typing:
            return [Note(from: 1_760, to: 1_600, start: 0, duration: 0.018, volume: 0.06, release: 0.014)]
        }
    }

    // Échantillons du son, entre -1 et 1.
    static func samples(for sound: UISound) -> [Float] {
        render(notes(for: sound))
    }

    static func render(_ notes: [Note]) -> [Float] {
        let length = notes.map { $0.start + $0.duration }.max() ?? 0
        var output = [Float](repeating: 0, count: Int((length * sampleRate).rounded(.up)) + 1)
        // Générateur pseudo-aléatoire déterministe pour le bruit (même son à chaque fois).
        var seed: UInt32 = 0x1234_5678
        for note in notes {
            let first = Int(note.start * sampleRate)
            let count = Int(note.duration * sampleRate)
            var phase = 0.0
            var lowPass = 0.0
            for index in 0..<count where first + index < output.count {
                let time = Double(index) / sampleRate
                let progress = Double(index) / Double(max(count - 1, 1))
                let frequency = note.from * pow(note.to / note.from, progress)
                phase += 2 * .pi * frequency / sampleRate
                let value: Double
                switch note.wave {
                case .sine:
                    value = sin(phase)
                case .triangle:
                    let cycle = (phase / (2 * .pi)).truncatingRemainder(dividingBy: 1)
                    value = 4 * abs(cycle - 0.5) - 1
                case .noise:
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let white = Double(seed) / Double(UInt32.max) * 2 - 1
                    // Coefficient du passe-bas tiré de la fréquence (qui monte avec le glissando).
                    let alpha = min(1, 2 * .pi * frequency / sampleRate)
                    lowPass += alpha * (white - lowPass)
                    value = lowPass * 2.2
                }
                output[first + index] += Float(value * note.volume * envelope(time: time, note: note))
            }
        }
        // Jamais au-delà de ±1 (notes superposées).
        let peak = output.map(abs).max() ?? 0
        if peak > 0.95 { output = output.map { $0 * 0.95 / peak } }
        return output
    }

    static func envelope(time: Double, note: Note) -> Double {
        let attack = min(1, time / max(note.attack, 0.0001))
        let remaining = note.duration - time
        let release = min(1, max(0, remaining / max(note.release, 0.0001)))
        return attack * release
    }
}
