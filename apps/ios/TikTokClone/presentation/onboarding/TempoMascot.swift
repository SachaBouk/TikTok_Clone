import SwiftUI

// Tempo, la mascotte de l'onboarding (ADR-075) : la note de musique du logo maison, avec des yeux, des humeurs, des
// clignements et des rebonds. Dessinée en SwiftUI, sans image ; jamais le logo ni les personnages de TikTok ou de
// Duolingo. Échos cyan et rose derrière, comme le logo, qui s'écartent quand elle est contente.
enum TempoMood: Equatable, Sendable {
    case happy, wink, surprised, party, thinking, neutral
}

struct TempoMascot: View {
    var size: CGFloat = 120
    var mood: TempoMood = .neutral
    // Chaque changement fait rebondir Tempo (écrasement puis étirement).
    var bounce: Int = 0
    var crowned = false

    var body: some View {
        TempoFigure(size: size, mood: mood, crowned: crowned)
            .keyframeAnimator(initialValue: Squash(), trigger: bounce) { content, value in
                content
                    .scaleEffect(x: value.scaleX, y: value.scaleY, anchor: .bottom)
                    .offset(y: value.offsetY)
            } keyframes: { _ in
                KeyframeTrack(\.scaleY) {
                    SpringKeyframe(0.82, duration: 0.1)
                    SpringKeyframe(1.12, duration: 0.18)
                    SpringKeyframe(0.96, duration: 0.14)
                    SpringKeyframe(1, duration: 0.2)
                }
                KeyframeTrack(\.scaleX) {
                    SpringKeyframe(1.14, duration: 0.1)
                    SpringKeyframe(0.92, duration: 0.18)
                    SpringKeyframe(1.02, duration: 0.14)
                    SpringKeyframe(1, duration: 0.2)
                }
                KeyframeTrack(\.offsetY) {
                    LinearKeyframe(0, duration: 0.1)
                    SpringKeyframe(-size * 0.22, duration: 0.2)
                    SpringKeyframe(0, duration: 0.32)
                }
            }
            .accessibilityHidden(true)
    }

    private struct Squash {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var offsetY: CGFloat = 0
    }
}

// Corps, échos, yeux, bouche et couronne, dans une boîte de 100 × 120 mise à l'échelle.
private struct TempoFigure: View {
    let size: CGFloat
    let mood: TempoMood
    let crowned: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    // Couleur du corps : sombre (logo noir), la même en mode sombre pour garder les yeux lisibles.
    static let body = Color(red: 0x16 / 255, green: 0x18 / 255, blue: 0x23 / 255)

    var body: some View {
        let unit = size / 100
        let spread: CGFloat = mood == .happy || mood == .party ? 1.6 : 1
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            // Respiration lente (idle) : léger gonflement.
            let breath = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * 2.2) * 0.018
            ZStack(alignment: .topLeading) {
                TempoShape().fill(Color.brandCyan).offset(x: -4 * unit * spread, y: -3 * unit * spread)
                TempoShape().fill(Color.brandPink).offset(x: 4 * unit * spread, y: 3 * unit * spread)
                TempoShape().fill(Self.body)
                eyes(unit: unit)
                mouth(unit: unit)
                if crowned { crown(unit: unit) }
            }
            .frame(width: 100 * unit, height: 120 * unit, alignment: .topLeading)
            .scaleEffect(1 + breath, anchor: .bottom)
        }
        .frame(width: size, height: size * 1.2)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: mood)
        .task(id: reduceMotion) { await blink() }
    }

    // Clignement toutes les 2,5 à 4,5 s.
    private func blink() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2500...4500)))
            withAnimation(.easeIn(duration: 0.06)) { blinking = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.08)) { blinking = false }
        }
    }

    private func eyes(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            eye(unit: unit, center: CGPoint(x: 29, y: 88), closedArc: mood == .happy || mood == .party)
            eye(unit: unit, center: CGPoint(x: 49, y: 83), closedArc: mood == .happy || mood == .party || mood == .wink)
        }
    }

    @ViewBuilder
    private func eye(unit: CGFloat, center: CGPoint, closedArc: Bool) -> some View {
        let radius: CGFloat = mood == .surprised ? 9 : 7.5
        if closedArc {
            // Œil fermé de joie : « ^ ».
            HappyEyeArc()
                .stroke(.white, style: StrokeStyle(lineWidth: 3.2 * unit, lineCap: .round))
                .frame(width: 12 * unit, height: 6 * unit)
                .position(x: center.x * unit, y: center.y * unit)
        } else {
            let look: CGPoint = mood == .thinking ? CGPoint(x: 2.6, y: -2.6) : CGPoint(x: 1.2, y: 0.4)
            let pupil: CGFloat = mood == .surprised ? 3.4 : 4.2
            ZStack {
                Circle().fill(.white)
                Circle().fill(Self.body)
                    .frame(width: pupil * 2 * unit, height: pupil * 2 * unit)
                    .offset(x: look.x * unit, y: look.y * unit)
                // Reflet.
                Circle().fill(.white)
                    .frame(width: 1.8 * unit, height: 1.8 * unit)
                    .offset(x: (look.x + 1.6) * unit, y: (look.y - 1.6) * unit)
            }
            .frame(width: radius * 2 * unit, height: radius * 2 * unit)
            .scaleEffect(x: 1, y: blinking ? 0.1 : 1)
            .position(x: center.x * unit, y: center.y * unit)
        }
    }

    @ViewBuilder
    private func mouth(unit: CGFloat) -> some View {
        let center = CGPoint(x: 41, y: 98)
        switch mood {
        case .surprised:
            Ellipse().fill(.white)
                .frame(width: 5 * unit, height: 6 * unit)
                .position(x: center.x * unit, y: center.y * unit)
        case .party, .happy:
            // Grand sourire ouvert, langue rose.
            SmileShape(open: true)
                .fill(Color.brandPink)
                .overlay(SmileShape(open: true).stroke(.white, lineWidth: 1.4 * unit))
                .frame(width: 13 * unit, height: 7 * unit)
                .position(x: center.x * unit, y: center.y * unit)
        case .thinking:
            Capsule().fill(.white)
                .frame(width: 6 * unit, height: 1.8 * unit)
                .position(x: (center.x + 2) * unit, y: center.y * unit)
        case .neutral, .wink:
            SmileShape(open: false)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.2 * unit, lineCap: .round))
                .frame(width: 10 * unit, height: 4 * unit)
                .position(x: center.x * unit, y: center.y * unit)
        }
    }

    private func crown(unit: CGFloat) -> some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 26 * unit))
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .rotationEffect(.degrees(-18))
            .position(x: 30 * unit, y: 62 * unit)
    }
}

// Note de musique : tête ovale inclinée, hampe, crochet. Coordonnées dans une boîte de 100 × 120.
struct TempoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100
        let sy = rect.height / 120
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        // Tête, inclinée de -20°.
        let head = Path(ellipseIn: CGRect(x: -31, y: -23, width: 62, height: 46))
            .applying(CGAffineTransform(rotationAngle: -.pi / 9))
            .applying(CGAffineTransform(translationX: 40, y: 91))
            .applying(CGAffineTransform(scaleX: sx, y: sy))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        path.addPath(head)
        // Hampe arrondie.
        path.addRoundedRect(
            in: CGRect(origin: point(60, 10), size: CGSize(width: 11 * sx, height: 80 * sy)), cornerSize: CGSize(width: 4 * sx, height: 4 * sy))
        // Crochet.
        path.move(to: point(64, 12))
        path.addQuadCurve(to: point(95, 36), control: point(90, 14))
        path.addQuadCurve(to: point(86, 68), control: point(101, 52))
        path.addQuadCurve(to: point(71, 44), control: point(86, 48))
        path.addLine(to: point(64, 40))
        path.closeSubpath()
        return path
    }
}

private struct HappyEyeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return path
    }
}

private struct SmileShape: Shape {
    let open: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6))
        if open { path.closeSubpath() }
        return path
    }
}

#Preview {
    VStack(spacing: 30) {
        HStack(spacing: 20) {
            TempoMascot(size: 90, mood: .neutral)
            TempoMascot(size: 90, mood: .happy)
            TempoMascot(size: 90, mood: .wink)
        }
        HStack(spacing: 20) {
            TempoMascot(size: 90, mood: .surprised)
            TempoMascot(size: 90, mood: .thinking)
            TempoMascot(size: 90, mood: .party, crowned: true)
        }
    }
    .padding()
}
