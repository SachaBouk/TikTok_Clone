import SwiftUI

// Pluie de confettis (ADR-075), aux couleurs du logo, dessinée dans un `Canvas`. Chaque changement de `trigger` en lance
// une ; rien avec « Réduire les animations ». Ne prend jamais les touchers.
struct ConfettiView: View {
    let trigger: Int
    var colors: [Color] = [.brandCyan, .brandPink, .white, Color(red: 1, green: 0.8, blue: 0.2)]
    var count = 90
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    private static let duration = 2.6

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Canvas { canvas, size in
                guard let start else { return }
                let time = context.date.timeIntervalSince(start)
                guard time < Self.duration else { return }
                for piece in pieces {
                    let x = size.width * piece.originX + piece.velocityX * time
                    let y = size.height * piece.originY + piece.velocityY * time + 520 * time * time
                    let fade = max(0, 1 - max(0, time - Self.duration + 0.6) / 0.6)
                    var context = canvas
                    context.opacity = fade
                    context.translateBy(x: x, y: y)
                    context.rotate(by: .degrees(piece.spin * time * 360))
                    // Le confetti « tourne sur lui-même » : sa largeur bat.
                    let flip = abs(cos(time * piece.flipSpeed))
                    let rect = CGRect(x: -piece.width / 2 * flip, y: -piece.height / 2, width: piece.width * max(flip, 0.15), height: piece.height)
                    context.fill(piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[piece.color]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { launch() }
    }

    private func launch() {
        guard !reduceMotion else { return }
        pieces = (0..<count).map { _ in Piece.random(colors: colors.count) }
        start = .now
        Task {
            try? await Task.sleep(for: .seconds(Self.duration))
            start = nil
        }
    }

    private struct Piece {
        var originX: Double
        var originY: Double
        var velocityX: Double
        var velocityY: Double
        var spin: Double
        var flipSpeed: Double
        var width: Double
        var height: Double
        var color: Int
        var round: Bool

        // Jaillissement depuis le haut du tiers central, vers le haut puis retombée.
        static func random(colors: Int) -> Piece {
            Piece(
                originX: .random(in: 0.3...0.7), originY: .random(in: 0.2...0.35),
                velocityX: .random(in: -260...260), velocityY: .random(in: -620 ... -180),
                spin: .random(in: -1.5...1.5), flipSpeed: .random(in: 4...10),
                width: .random(in: 7...11), height: .random(in: 10...16),
                color: .random(in: 0..<colors), round: Int.random(in: 0..<5) == 0)
        }
    }
}
