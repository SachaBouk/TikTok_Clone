import SwiftUI

// Écrans de l'onboarding animé (ADR-075) avant les tutoriels : accueil en orbite, Tempo qui se présente, questions,
// préparation, « Bienvenue » (compte créé) et consentement à la mesure d'audience.

// MARK: Accueil

// Façon Luma : logo au centre sur fond noir (suite de l'écran de lancement), icônes de l'app en orbite qui arrivent une à
// une, lueur rose et cyan qui respire ; « C'est parti » et « J'ai déjà un compte ».
struct OnboardingWelcomeView: View {
    let model: OnboardingFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = 0
    @State private var titleShown = false

    private static let orbit: [OrbitItem] = [
        OrbitItem(ring: 1, angle: 20, kind: .symbol("heart.fill", .brandPink)),
        OrbitItem(ring: 0, angle: 110, kind: .face("😎", [.brandCyan, .blue])),
        OrbitItem(ring: 1, angle: 160, kind: .symbol("bookmark.fill", .yellow)),
        OrbitItem(ring: 0, angle: 230, kind: .live),
        OrbitItem(ring: 1, angle: 260, kind: .face("🥳", [.orange, .brandPink])),
        OrbitItem(ring: 0, angle: 340, kind: .symbol("gift.fill", .orange)),
        OrbitItem(ring: 1, angle: 300, kind: .symbol("bubble.right.fill", .white)),
        OrbitItem(ring: 0, angle: 30, kind: .plus),
        OrbitItem(ring: 1, angle: 80, kind: .face("🤩", [.purple, .brandCyan])),
        OrbitItem(ring: 1, angle: 210, kind: .symbol("arrowshape.turn.up.right.fill", .white)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            orbit
                .frame(maxWidth: .infinity)
                .frame(height: 400)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                AppWordmark(size: 22)
                Text("Tes vidéos.")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Ton rythme.")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: [.brandCyan, .brandPink], startPoint: .leading, endPoint: .trailing))
            }
            .multilineTextAlignment(.center)
            .opacity(titleShown ? 1 : 0)
            .offset(y: titleShown ? 0 : 16)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Button("C’est parti") { model.start() }
                    .buttonStyle(ChunkyButtonStyle())
                    .accessibilityIdentifier("onboarding.start")
                Button("J’ai déjà un compte") { model.chooseLogin() }
                    .buttonStyle(ChunkyOutlineButtonStyle(foreground: .white))
                    .accessibilityIdentifier("onboarding.login")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .opacity(titleShown ? 1 : 0)
        }
        .background(Color("LaunchBackground").ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task { await appear() }
    }

    private var orbit: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(time * 1.6) + 1) / 2
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let radii: [CGFloat] = [105, 170]
                ZStack {
                    // Lueur qui respire derrière le logo.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.brandPink.opacity(0.55), Color.brandCyan.opacity(0.25), .clear], center: .center, startRadius: 4,
                                endRadius: 140)
                        )
                        .frame(width: 280, height: 280)
                        .scaleEffect(0.85 + pulse * 0.2)
                        .position(center)
                    ForEach(radii.indices, id: \.self) { index in
                        Circle()
                            .stroke(.white.opacity(0.13), lineWidth: 1.2)
                            .frame(width: radii[index] * 2, height: radii[index] * 2)
                            .position(center)
                    }
                    AppLogo(size: 64)
                        .scaleEffect(appeared > 0 ? 1 + pulse * 0.05 : 0.4)
                        .opacity(appeared > 0 ? 1 : 0)
                        .position(center)
                    ForEach(Array(Self.orbit.enumerated()), id: \.offset) { index, item in
                        // Les deux anneaux tournent en sens contraire, lentement.
                        let speed = item.ring == 0 ? 9.0 : -6.0
                        let angle = Angle.degrees(item.angle + time * speed).radians
                        let radius = radii[item.ring]
                        OrbitBadge(kind: item.kind)
                            .scaleEffect(appeared > index + 1 ? 1 : 0.01)
                            .opacity(appeared > index + 1 ? 1 : 0)
                            .position(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // Logo, puis une icône toutes les 90 ms (tic à chacune), puis le titre et les boutons.
    private func appear() async {
        guard appeared == 0 else { return }
        if reduceMotion {
            appeared = Self.orbit.count + 1
            titleShown = true
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.spring(duration: 0.5, bounce: 0.5)) { appeared = 1 }
        model.feedback?.play(.pop)
        for index in Self.orbit.indices {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.spring(duration: 0.45, bounce: 0.6)) { appeared = index + 2 }
            if index.isMultiple(of: 2) { model.feedback?.play(.tick) }
        }
        withAnimation(.spring(duration: 0.6)) { titleShown = true }
    }

    private struct OrbitItem {
        let ring: Int
        let angle: Double
        let kind: OrbitBadge.Kind
    }
}

private struct OrbitBadge: View {
    enum Kind {
        case symbol(String, Color)
        case face(String, [Color])
        case live
        case plus
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color(white: 0.16)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        case .face(let emoji, let colors):
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 58, height: 58)
                .background(Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
        case .live:
            Text("LIVE")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient(colors: [.brandPink, .purple], startPoint: .leading, endPoint: .trailing)))
        case .plus:
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 46, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(.white))
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.brandCyan).offset(x: -3))
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.brandPink).offset(x: 3))
        }
    }
}

// MARK: Tempo se présente

// Tempo tombe, rebondit et salue sous des confettis ; deux répliques dans la bulle.
struct OnboardingHelloView: View {
    let model: OnboardingFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var bounce = 0
    @State private var confetti = 0
    @State private var line = 0

    private static let lines = ["Salut ! Moi, c’est Tempo.", "Je vais te montrer comment tout marche ici. C’est parti ?"]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            SpeechBubble(text: Self.lines[line], font: .title3.weight(.bold), tail: .bottom)
                .padding(.horizontal, 32)
                .opacity(landed ? 1 : 0)
            TempoMascot(size: 150, mood: line == 0 ? .happy : .wink, bounce: bounce)
                .offset(y: landed ? 0 : -700)
                .onTapGesture {
                    bounce += 1
                    model.feedback?.play(.pop)
                }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .overlay { ConfettiView(trigger: confetti) }
        .onboardingBottomBar {
            Button("Continuer") { model.next(from: .hello) }
                .buttonStyle(ChunkyButtonStyle())
                .accessibilityIdentifier("onboarding.hello.next")
        }
        .task { await enter() }
    }

    private func enter() async {
        guard !landed else { return }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.25)) { landed = true }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 450))
        bounce += 1
        confetti += 1
        model.feedback?.play(.celebrate)
        try? await Task.sleep(for: .seconds(2.2))
        withAnimation { line = 1 }
        bounce += 1
    }
}

// MARK: Questions

struct OnboardingQuestionView: View {
    let model: OnboardingFlowModel
    let step: OnboardingStep
    @State private var bounce = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TempoSays(text: tempoLine, mood: mood, size: 70, bounce: bounce)
                VStack(spacing: 12) {
                    if step == .source {
                        ForEach(OnboardingSource.allCases, id: \.self) { source in
                            ChoiceCard(title: source.title, symbol: source.emoji, isSelected: model.answers.source == source) {
                                model.choose(source)
                                bounce += 1
                            }
                            .accessibilityIdentifier("onboarding.source.\(source.rawValue)")
                        }
                    } else {
                        ForEach(OnboardingGoal.allCases, id: \.self) { goal in
                            ChoiceCard(title: goal.title, subtitle: goal.subtitle, symbol: goal.emoji, isSelected: model.answers.goal == goal) {
                                model.choose(goal)
                                bounce += 1
                            }
                            .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onboardingBottomBar {
            Button("Continuer") { model.next(from: step) }
                .buttonStyle(ChunkyButtonStyle())
                .disabled(!isAnswered)
                .accessibilityIdentifier("onboarding.question.next")
        }
    }

    private var isAnswered: Bool {
        step == .source ? model.answers.source != nil : model.answers.goal != nil
    }

    private var tempoLine: String {
        if step == .source {
            return model.answers.source == nil ? "Comment as-tu connu TikTok Clone ?" : "Merci ! Ça m’aide beaucoup."
        }
        switch model.answers.goal {
        case nil: return "Tu viens surtout pour…"
        case .watch: return "Installe-toi, ça va défiler !"
        case .create: return "Une future star ? Je te montrerai la caméra 🎬"
        case .both: return "Le meilleur des deux mondes !"
        }
    }

    private var mood: TempoMood {
        let answered = isAnswered
        return answered ? .happy : .thinking
    }
}

extension OnboardingSource {
    var title: String {
        switch self {
        case .friends: "Amis ou famille"
        case .social: "Réseaux sociaux"
        case .appStore: "App Store"
        case .web: "Recherche sur le web"
        case .video: "Vidéo en ligne"
        case .other: "Autre"
        }
    }

    var emoji: String {
        switch self {
        case .friends: "👫"
        case .social: "📱"
        case .appStore: "🛍️"
        case .web: "🔎"
        case .video: "▶️"
        case .other: "✨"
        }
    }
}

extension OnboardingGoal {
    var title: String {
        switch self {
        case .watch: "Regarder des vidéos"
        case .create: "Créer et publier"
        case .both: "Les deux"
        }
    }

    var subtitle: String {
        switch self {
        case .watch: "Découvrir et me détendre"
        case .create: "Filmer, monter, partager"
        case .both: "Un peu de tout"
        }
    }

    var emoji: String {
        switch self {
        case .watch: "🍿"
        case .create: "🎬"
        case .both: "🤩"
        }
    }
}

// MARK: Préparation

// Façon Duolingo : Tempo danse pendant 1,8 s, puis l'écran suivant arrive tout seul.
struct OnboardingPreparingView: View {
    let model: OnboardingFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0
    @State private var wiggle = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            TempoMascot(size: 130, mood: .party, bounce: bounce)
                .rotationEffect(.degrees(wiggle ? 8 : -8), anchor: .bottom)
            DotsLoader()
            VStack(spacing: 8) {
                Text("Je prépare ton espace…")
                    .font(.title2.weight(.heavy))
                Text("Plus que quelques secondes !")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task { await dance() }
    }

    private func dance() async {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) { wiggle = true }
        }
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            bounce += 1
            model.feedback?.play(.tick)
        }
        guard !Task.isCancelled, model.current == .preparing else { return }
        model.feedback?.play(.success)
        model.next(from: .preparing)
    }
}

// MARK: Bienvenue

// Compte créé : grande pluie de confettis, Tempo en fête.
struct OnboardingAccountCreatedView: View {
    let model: OnboardingFlowModel
    @State private var bounce = 0
    @State private var confetti = 0
    @State private var shown = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TempoMascot(size: 150, mood: .party, bounce: bounce)
                .scaleEffect(shown ? 1 : 0.3)
                .onTapGesture {
                    bounce += 1
                    confetti += 1
                    model.feedback?.play(.pop)
                }
            VStack(spacing: 10) {
                Text("Bienvenue,")
                    .font(.system(size: 32, weight: .heavy))
                Text("@\(model.signup?.username ?? "")")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: [.brandCyan, .brandPink], startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Ton compte est prêt. Encore quelques astuces et c’est parti !")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .opacity(shown ? 1 : 0)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .overlay { ConfettiView(trigger: confetti, count: 140) }
        .onboardingBottomBar {
            Button("Continuer") { model.next(from: .accountCreated) }
                .buttonStyle(ChunkyButtonStyle())
                .accessibilityIdentifier("onboarding.welcome.next")
        }
        .task {
            guard !shown else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0.5)) { shown = true }
            try? await Task.sleep(for: .milliseconds(250))
            bounce += 1
            confetti += 1
        }
    }
}

// MARK: Consentement

// Mesure d'audience (ADR-013) : même choix qu'avant, dans le parcours (façon Luma : faux graphique qui monte).
struct OnboardingConsentView: View {
    let model: OnboardingFlowModel
    @State private var grown = false

    private static let bars: [CGFloat] = [0.35, 0.55, 0.45, 0.75, 1]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TempoSays(text: "Tu veux m’aider à améliorer l’app ?", mood: .thinking, size: 70)
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(Self.bars.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [.brandCyan, .brandPink], startPoint: .bottom, endPoint: .top))
                            .frame(height: grown ? 150 * Self.bars[index] : 8)
                            .animation(.spring(duration: 0.7, bounce: 0.4).delay(Double(index) * 0.08), value: grown)
                    }
                }
                .frame(height: 160, alignment: .bottom)
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
                .accessibilityHidden(true)
                Text(AnalyticsConsentView.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onboardingBottomBar {
            Button("Oui, j’aide") { model.answerConsent(true) }
                .buttonStyle(ChunkyButtonStyle())
                .accessibilityIdentifier("onboarding.consent.accept")
            Button("Non merci") { model.answerConsent(false) }
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(height: 40)
                .accessibilityIdentifier("onboarding.consent.decline")
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            grown = true
            model.feedback?.play(.tick)
        }
    }
}
