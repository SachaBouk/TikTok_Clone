import SwiftUI

// Éléments communs de l'onboarding animé (ADR-075) : bulle de Tempo qui s'écrit, barre du haut (‹, progression,
// « Plus tard »), bouton en relief façon Duolingo, carte de réponse.

// Bulle de Tempo : le texte s'écrit lettre à lettre (~30 ms), avec un tic discret ; un toucher l'affiche en entier.
struct SpeechBubble: View {
    let text: String
    var font: Font = .title3.weight(.semibold)
    // Pointe à gauche (Tempo à gauche) ou en bas (Tempo dessous).
    var tail: Edge = .leading
    @Environment(\.onboardingFeedback) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        // Texte complet invisible : la bulle garde sa taille finale pendant l'écriture.
        ZStack(alignment: .topLeading) {
            Text(text).hidden()
            Text(String(text.prefix(shown)))
        }
        .font(font)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            BubbleShape(tail: tail)
                .fill(Color(.systemBackground))
                .overlay(BubbleShape(tail: tail).stroke(Color(.systemGray4), lineWidth: 2))
        }
        .contentShape(Rectangle())
        .onTapGesture { shown = text.count }
        .task(id: text) { await write() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func write() async {
        guard !reduceMotion else {
            shown = text.count
            return
        }
        shown = 0
        for index in 1...max(text.count, 1) {
            try? await Task.sleep(for: .milliseconds(28))
            guard !Task.isCancelled, shown < text.count else { return }
            shown = index
            if index % 3 == 0 { feedback?.play(.typing) }
        }
    }
}

private struct BubbleShape: Shape {
    let tail: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 16)
        switch tail {
        case .leading:
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY - 8))
            path.addLine(to: CGPoint(x: rect.minX - 10, y: rect.midY + 2))
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.midY + 8))
        case .bottom:
            path.move(to: CGPoint(x: rect.midX - 9, y: rect.maxY - 1))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + 11))
            path.addLine(to: CGPoint(x: rect.midX + 9, y: rect.maxY - 1))
        default:
            break
        }
        return path
    }
}

// Tempo en petit, à gauche, et sa bulle (questions, étapes de l'inscription, tutoriels).
struct TempoSays: View {
    let text: String
    var mood: TempoMood = .neutral
    var size: CGFloat = 64
    var bounce = 0

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            TempoMascot(size: size, mood: mood, bounce: bounce)
            SpeechBubble(text: text, font: .body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Barre de progression : dégradé cyan → rose, avancée avec un ressort, reflet en haut comme Duolingo.
struct OnboardingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(LinearGradient(colors: [.brandCyan, .brandPink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(16, proxy.size.width * progress))
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.35)).frame(height: 4).padding(.horizontal, 8).padding(.top, 3)
                    }
            }
        }
        .frame(height: 16)
        .animation(.spring(duration: 0.6, bounce: 0.35), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progression")
        .accessibilityValue("\(Int(progress * 100)) %")
    }
}

// ‹, barre de progression et action à droite (« Plus tard », « Passer », ×).
struct OnboardingTopBar: View {
    var progress: Double?
    var back: (() -> Void)?
    var trailingTitle: String?
    var trailing: (() -> Void)?
    var trailingIdentifier = "onboarding.trailing"

    var body: some View {
        HStack(spacing: 14) {
            if let back {
                Button("Retour", systemImage: "arrow.left", action: back)
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(.systemGray))
                    .frame(width: 32, height: 44)
                    .accessibilityIdentifier("onboarding.back")
            }
            if let progress {
                OnboardingProgressBar(progress: progress)
            } else {
                Spacer()
            }
            if let trailingTitle, let trailing {
                Button(trailingTitle, action: trailing)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(.systemGray))
                    .accessibilityIdentifier(trailingIdentifier)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
    }
}

// Bouton en relief façon Duolingo : fond plein, bord inférieur plus sombre, s'enfonce au toucher. Gris s'il est
// désactivé.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = .brandPink
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let depth: CGFloat = 5
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isEnabled ? foreground : Color(.systemGray2))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? color : Color(.systemGray5))
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? color.mix(with: .black, by: 0.25) : Color(.systemGray4))
                    .offset(y: pressed ? 0 : depth)
            )
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .animation(.spring(duration: 0.15), value: pressed)
            .contentShape(Rectangle())
    }
}

// Bouton à contour en relief (« J'ai déjà un compte »).
struct ChunkyOutlineButtonStyle: ButtonStyle {
    var foreground: Color = .brandPink

    func makeBody(configuration: Configuration) -> some View {
        let depth: CGFloat = 4
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.systemGray4), lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray4)).offset(y: configuration.isPressed ? 0 : depth)
            )
            .offset(y: configuration.isPressed ? depth : 0)
            .padding(.bottom, depth)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

// Carte de réponse : icône, texte ; choisie, bord cyan et fond teinté, avec un petit rebond.
struct ChoiceCard: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(symbol)
                    .font(.title2)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.brandPink : Color(.systemGray4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(
                // Fond opaque, puis la teinte : la couche du relief ne doit pas transparaître.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.brandCyan.opacity(isSelected ? 0.14 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandCyan : Color(.systemGray4), lineWidth: 2)
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.brandCyan.mix(with: .black, by: 0.15) : Color(.systemGray4))
                    .offset(y: 3)
            )
            .scaleEffect(isSelected ? 1.02 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    // Mise en page d'un écran de l'onboarding : contenu, puis bouton en bas.
    func onboardingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) { bar() }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
        }
    }
}
