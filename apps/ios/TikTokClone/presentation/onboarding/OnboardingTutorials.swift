import SwiftUI

// Tutoriels interactifs de l'onboarding (ADR-075) : il faut faire le geste sur le téléphone dessiné pour continuer
// (balayer vers le haut, toucher deux fois, rester appuyé sur un côté, balayer vers la gauche, filmer). « Passer » reste
// possible, et VoiceOver propose une action qui fait le geste.

struct OnboardingTutorialView: View {
    let model: OnboardingFlowModel
    let step: OnboardingStep
    @State private var bounce = 0

    private var isDone: Bool { model.tutorialsCompleted.contains(step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer(minLength: 12)
            phone
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            TempoSays(text: isDone ? doneLine : hintLine, mood: isDone ? .party : .neutral, size: 52, bounce: bounce)
                .padding(.horizontal, 20)
        }
        .onboardingBottomBar {
            Button("Continuer") { model.next(from: step) }
                .buttonStyle(ChunkyButtonStyle())
                .disabled(!isDone)
                .accessibilityIdentifier("onboarding.tutorial.next")
        }
        .onChange(of: isDone) { _, done in if done { bounce += 1 } }
    }

    @ViewBuilder
    private var phone: some View {
        let complete = { model.tutorialCompleted(step) }
        Group {
            switch step {
            case .swipeUp: SwipeUpDemo(feedback: model.feedback, completed: complete)
            case .doubleTapLike: DoubleTapDemo(feedback: model.feedback, completed: complete)
            case .fastForward: FastForwardDemo(feedback: model.feedback, completed: complete)
            case .swipeToProfile: SwipeToProfileDemo(feedback: model.feedback, completed: complete)
            default: CreateDemo(feedback: model.feedback, completed: complete)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle)
        .accessibilityAction(named: "Faire le geste", complete)
        .accessibilityIdentifier("onboarding.tutorial.\(step.rawValue)")
    }

    private var title: String {
        switch step {
        case .swipeUp: "Balaie vers le haut"
        case .doubleTapLike: "Touche deux fois"
        case .fastForward: "Reste appuyé sur un côté"
        case .swipeToProfile: "Balaie vers la gauche"
        default: "Touche + pour créer"
        }
    }

    private var subtitle: String {
        switch step {
        case .swipeUp: "Fais glisser la vidéo vers le haut pour passer à la suivante."
        case .doubleTapLike: "Touche deux fois la vidéo pour l’aimer."
        case .fastForward: "Garde le doigt sur un bord de la vidéo : elle passe en vitesse ×2."
        case .swipeToProfile: "Fais glisser la vidéo vers la gauche pour ouvrir le profil de son auteur."
        default: "Le « + » ouvre la caméra. Touche le bouton rose pour filmer."
        }
    }

    private var hintLine: String {
        switch step {
        case .swipeUp: "Essaie sur le téléphone !"
        case .doubleTapLike: "Tape-tape, sur la vidéo !"
        case .fastForward: "Appuie sur le bord droit… et ne lâche pas !"
        case .swipeToProfile: "Glisse de droite à gauche."
        default: "À toi de filmer !"
        }
    }

    private var doneLine: String {
        switch step {
        case .swipeUp: "Bravo, c’est exactement ça !"
        case .doubleTapLike: "Elle va adorer ton j’aime ❤️"
        case .fastForward: "Pratique pour aller à l’essentiel !"
        case .swipeToProfile: "Tu peux le suivre depuis son profil."
        default: "Coupé ! Une vraie pro de la caméra 🎬"
        }
    }
}

// MARK: Téléphone dessiné

// Téléphone stylisé (bord noir, écran arrondi) qui contient la démonstration.
struct DemoPhone<Content: View>: View {
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 33, style: .continuous).fill(Color.black))
        .overlay(alignment: .top) {
            Capsule().fill(Color.black).frame(width: 64, height: 18).padding(.top, 14)
        }
        .aspectRatio(9 / 18.5, contentMode: .fit)
        .frame(maxHeight: 400)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

// Fausse vidéo : dégradé, gros emoji, auteur et légende, colonne de droite.
struct DemoVideo: View {
    let index: Int
    var liked = false
    var likes = 128

    static let looks: [(colors: [Color], emoji: String, author: String, caption: String)] = [
        (
            [Color(red: 0.55, green: 0.67, blue: 0.95), Color(red: 0.98, green: 0.73, blue: 0.75)], "🌅", "@lea.voyage",
            "Coucher de soleil à Biarritz #été"
        ),
        (
            [Color(red: 0.99, green: 0.55, blue: 0.35), Color(red: 0.6, green: 0.15, blue: 0.4)], "🍜", "@chef.nathan",
            "Ramen maison en 10 min #cuisine"
        ),
        (
            [Color(red: 0.15, green: 0.85, blue: 0.83), Color(red: 0.2, green: 0.25, blue: 0.55)], "🐶", "@ines.et.pixel",
            "Il a enfin compris 😂 #humour"
        ),
        (
            [Color(red: 0.55, green: 0.3, blue: 0.9), Color(red: 0.95, green: 0.35, blue: 0.6)], "🎸", "@sam.music",
            "Premier riff de la journée #musique"
        ),
    ]

    var body: some View {
        let look = Self.looks[index % Self.looks.count]
        ZStack {
            LinearGradient(colors: look.colors, startPoint: .top, endPoint: .bottom)
            Text(look.emoji).font(.system(size: 72))
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(look.author).font(.system(size: 12, weight: .bold))
                        Text(look.caption).font(.system(size: 11)).lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    Spacer(minLength: 6)
                    VStack(spacing: 12) {
                        Circle().fill(.white).frame(width: 30, height: 30).overlay(Text(look.emoji).font(.system(size: 15)))
                        column("heart.fill", "\(likes + (liked ? 1 : 0))", color: liked ? .brandPink : .white)
                        column("ellipsis.bubble.fill", "24", color: .white)
                        column("bookmark.fill", "9", color: .white)
                        column("arrowshape.turn.up.right.fill", "5", color: .white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
    }

    private func column(_ symbol: String, _ count: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
            Text(count).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
        }
        .shadow(radius: 2)
    }
}

// Main qui montre le geste en boucle, tant que rien n'a été fait.
private struct HandHint: View {
    enum Motion {
        case up, left, tap, hold
    }

    let motion: Motion
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let cycle = 1.8
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
            let eased = time < 0.7 ? (1 - cos(time / 0.7 * .pi)) / 2 : 1
            let fade = time < 0.08 ? time / 0.08 : time > 0.85 ? max(0, (1 - time) / 0.15) : 1
            ZStack {
                if motion == .tap || motion == .hold {
                    let ring = motion == .tap ? (time * 2).truncatingRemainder(dividingBy: 1) : time
                    Circle()
                        .stroke(.white.opacity(0.8 * (1 - ring)), lineWidth: 3)
                        .frame(width: 30 + ring * 50, height: 30 + ring * 50)
                }
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                    .offset(x: 14, y: 26)
            }
            .offset(offset(eased: reduceMotion ? 0.5 : eased))
            .opacity(reduceMotion ? 1 : (motion == .up || motion == .left ? fade : 1))
        }
        .allowsHitTesting(false)
    }

    private func offset(eased: Double) -> CGSize {
        switch motion {
        case .up: CGSize(width: size.width * 0.12, height: size.height * (0.25 - 0.4 * eased))
        case .left: CGSize(width: size.width * (0.28 - 0.5 * eased), height: size.height * 0.05)
        case .tap: .zero
        case .hold: CGSize(width: size.width * 0.32, height: 0)
        }
    }
}

// MARK: Balayer vers le haut

private struct SwipeUpDemo: View {
    let feedback: OnboardingFeedback?
    let completed: () -> Void
    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var interacted = false

    var body: some View {
        DemoPhone { size in
            VStack(spacing: 0) {
                DemoVideo(index: index).frame(height: size.height)
                DemoVideo(index: index + 1).frame(height: size.height)
            }
            .offset(y: min(0, drag))
            .frame(height: size.height, alignment: .top)
            .overlay { if !interacted { HandHint(motion: .up, size: size) } }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        interacted = true
                        drag = value.translation.height
                    }
                    .onEnded { value in
                        let passed = -value.predictedEndTranslation.height > size.height * 0.3 || -value.translation.height > size.height * 0.22
                        guard passed else {
                            withAnimation(.spring(duration: 0.35)) { drag = 0 }
                            return
                        }
                        feedback?.play(.advance)
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                            drag = -size.height
                        } completion: {
                            index += 1
                            drag = 0
                            completed()
                        }
                    }
            )
        }
    }
}

// MARK: Double toucher

private struct DoubleTapDemo: View {
    let feedback: OnboardingFeedback?
    let completed: () -> Void
    @State private var liked = false
    @State private var hearts: [TapHeart] = []
    @State private var interacted = false

    var body: some View {
        DemoPhone { size in
            DemoVideo(index: 2, liked: liked)
                .overlay {
                    ForEach(hearts) { heart in
                        BurstHeart().position(heart.point)
                    }
                }
                .overlay { if !interacted { HandHint(motion: .tap, size: size) } }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2).onEnded { value in
                        interacted = true
                        let heart = TapHeart(point: value.location)
                        hearts.append(heart)
                        feedback?.play(.pop)
                        withAnimation(.spring(duration: 0.3, bounce: 0.6)) { liked = true }
                        completed()
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            hearts.removeAll { $0.id == heart.id }
                        }
                    }
                )
        }
    }

    private struct TapHeart: Identifiable {
        let id = UUID()
        let point: CGPoint
    }
}

// Cœur qui éclate : grossit avec un rebond, puis monte et s'efface.
private struct BurstHeart: View {
    @State private var popped = false
    @State private var gone = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 90))
            .foregroundStyle(LinearGradient(colors: [.brandPink, Color(red: 1, green: 0.4, blue: 0.5)], startPoint: .top, endPoint: .bottom))
            .shadow(color: .brandPink.opacity(0.5), radius: 10)
            .rotationEffect(.degrees(popped ? -10 : 8))
            .scaleEffect(popped ? 1.1 : 0.3)
            .offset(y: gone ? -60 : 0)
            .opacity(gone ? 0 : 1)
            .allowsHitTesting(false)
            .task {
                withAnimation(.spring(duration: 0.35, bounce: 0.6)) { popped = true }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeIn(duration: 0.4)) { gone = true }
            }
    }
}

// MARK: Vitesse ×2

private struct FastForwardDemo: View {
    let feedback: OnboardingFeedback?
    let completed: () -> Void
    @State private var progress = 0.0
    @State private var isFast = false
    @State private var fastTime = 0.0
    @State private var interacted = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        DemoPhone { size in
            DemoVideo(index: 3)
                .overlay(alignment: .top) {
                    if isFast {
                        Label("Vitesse ×2", systemImage: "forward.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .padding(.top, 44)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.white).frame(width: bar.size.width * progress)
                        }
                    }
                    .frame(height: isFast ? 5 : 3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
                .overlay { if !interacted { HandHint(motion: .hold, size: size) } }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard holdTask == nil, !isFast else { return }
                            let x = value.startLocation.x / size.width
                            guard x < 0.35 || x > 0.65 else { return }
                            interacted = true
                            holdTask = Task { await hold() }
                        }
                        .onEnded { _ in release() }
                )
                .task { await play() }
        }
    }

    // Lecture : la barre avance, deux fois plus vite en ×2.
    private func play() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            let step = 0.033 / 9 * (isFast ? 2 : 1)
            progress = (progress + step).truncatingRemainder(dividingBy: 1)
            if isFast {
                fastTime += 0.033
                if fastTime >= 0.8 { completed() }
            }
        }
    }

    // Appui long (0,35 s) : vitesse ×2, petite vibration toutes les 0,3 s tant que le doigt reste.
    private func hold() async {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.25)) { isFast = true }
        feedback?.play(.speedUp)
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { feedback?.play(.rumble) }
        }
    }

    private func release() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.spring(duration: 0.25)) { isFast = false }
    }
}

// MARK: Profil de l'auteur

private struct SwipeToProfileDemo: View {
    let feedback: OnboardingFeedback?
    let completed: () -> Void
    @State private var drag: CGFloat = 0
    @State private var shown = false
    @State private var interacted = false

    var body: some View {
        DemoPhone { size in
            let offset = shown ? -size.width : min(0, drag)
            ZStack(alignment: .leading) {
                DemoVideo(index: 0)
                    .frame(width: size.width)
                    .offset(x: offset * 0.3)
                DemoProfile(onBack: {
                    feedback?.play(.tap)
                    withAnimation(.spring(duration: 0.4)) {
                        shown = false
                        drag = 0
                    }
                })
                .frame(width: size.width)
                .offset(x: size.width + offset)
                .shadow(color: .black.opacity(0.2), radius: 10)
            }
            .overlay { if !interacted { HandHint(motion: .left, size: size) } }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard !shown else { return }
                        interacted = true
                        drag = value.translation.width
                    }
                    .onEnded { value in
                        guard !shown else { return }
                        let passed = -value.predictedEndTranslation.width > size.width * 0.45 || -value.translation.width > size.width * 0.35
                        if passed { feedback?.play(.advance) }
                        withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
                            shown = passed
                            drag = 0
                        }
                        if passed { completed() }
                    }
            )
        }
    }
}

private struct DemoProfile: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Retour", systemImage: "chevron.left", action: onBack)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal, 12)
            Text("🌅")
                .font(.system(size: 38))
                .frame(width: 70, height: 70)
                .background(Circle().fill(LinearGradient(colors: DemoVideo.looks[0].colors, startPoint: .top, endPoint: .bottom)))
            Text("Léa").font(.system(size: 16, weight: .heavy))
            Text("@lea.voyage").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                stat("312", "Suivis")
                stat("12,4 k", "Followers")
                stat("98 k", "J’aime")
            }
            Text("Suivre")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 120, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.brandPink))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(0..<6, id: \.self) { index in
                    LinearGradient(colors: DemoVideo.looks[index % 4].colors, startPoint: .top, endPoint: .bottom)
                        .aspectRatio(3 / 4, contentMode: .fit)
                }
            }
            Spacer(minLength: 0)
        }
        // En haut de l'écran : la grille ne doit pas faire remonter l'en-tête sous l'encoche.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(Color(.systemBackground))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 13, weight: .bold))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

// MARK: Créer

// Barre d'onglets avec le « + » ; le toucher ouvre la caméra ; le bouton rose remplit trois segments.
private struct CreateDemo: View {
    let feedback: OnboardingFeedback?
    let completed: () -> Void
    @State private var cameraOpen = false
    @State private var segments = 0
    @State private var recording = false

    var body: some View {
        DemoPhone { size in
            ZStack {
                DemoVideo(index: 1)
                    .overlay(alignment: .bottom) { tabBar }
                if cameraOpen {
                    camera(size: size)
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(["house.fill", "person.2", "plus", "message", "person"], id: \.self) { symbol in
                if symbol == "plus" {
                    Button {
                        feedback?.play(.advance)
                        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { cameraOpen = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.brandCyan).offset(x: -3))
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.brandPink).offset(x: 3))
                    }
                    .buttonStyle(.plain)
                    .phaseAnimator([1.0, 1.12]) { content, scale in
                        content.scaleEffect(cameraOpen ? 1 : scale)
                    } animation: { _ in
                        .easeInOut(duration: 0.6)
                    }
                    .accessibilityLabel("Créer")
                } else {
                    Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.white.opacity(0.85))
                }
                if symbol != "person" { Spacer() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.black)
    }

    private func camera(size: CGSize) -> some View {
        ZStack {
            Color(white: 0.08)
            Text("🙋‍♀️").font(.system(size: 80)).opacity(0.85)
            VStack {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule().fill(index < segments ? Color.brandPink : Color.white.opacity(0.3)).frame(height: 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 40)
                Spacer()
                Button {
                    record()
                } label: {
                    ZStack {
                        Circle().stroke(.white.opacity(0.6), lineWidth: 4).frame(width: 64, height: 64)
                        RoundedRectangle(cornerRadius: recording ? 6 : 26)
                            .fill(Color.brandPink)
                            .frame(width: recording ? 26 : 52, height: recording ? 26 : 52)
                    }
                }
                .buttonStyle(.plain)
                .disabled(recording || segments == 3)
                .padding(.bottom, 28)
                .accessibilityLabel("Filmer")
            }
        }
    }

    private func record() {
        recording = true
        feedback?.play(.tap)
        Task {
            for index in 1...3 {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.2)) { segments = index }
                feedback?.play(.tick)
            }
            withAnimation { recording = false }
            completed()
        }
    }
}
