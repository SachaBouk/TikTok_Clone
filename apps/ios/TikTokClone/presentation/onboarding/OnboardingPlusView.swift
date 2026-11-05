import SwiftUI

// Paywall « Plus » de fin d'onboarding (ADR-075, façon Headspace) : Tempo couronné, bascule Annuel / Mensuel, frise de
// ce qui se passe (aujourd'hui, chaque mois ou chaque année, quand tu veux), avantages en cascade. Pas d'essai gratuit
// (ADR-073). « Plus tard » (×) termine le parcours. Mêmes achats que le paywall du menu (`PlusModel`).
struct OnboardingPlusView: View {
    let model: OnboardingFlowModel
    let plus: PlusModel
    @Environment(AnalyticsModel.self) private var analytics
    @State private var period: PlusPeriod = .annual
    @State private var shown = false
    @State private var confetti = 0
    @State private var bounce = 0

    private var selected: PlusOffer? { plus.offers.first { $0.period == period } ?? plus.offers.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                if plus.isActive {
                    activeCard
                } else {
                    periodPicker
                    timeline
                    benefits
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background {
            LinearGradient(
                colors: [Color.brandCyan.opacity(0.16), Color(.systemBackground), Color.brandPink.opacity(0.14)], startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .overlay { ConfettiView(trigger: confetti, colors: [.yellow, .orange, .brandPink, .brandCyan, .white], count: 140) }
        .onboardingBottomBar { bottomBar }
        .task {
            model.paywallShown()
            analytics.track(.plusPaywallViewed(source: .onboarding))
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) { shown = true }
            bounce += 1
            async let status: Void = plus.refresh()
            async let offers: Void = plus.loadOffers()
            _ = await (status, offers)
        }
        .onChange(of: plus.justActivated) { _, activated in
            guard activated else { return }
            confetti += 1
            bounce += 1
            model.feedback?.play(.celebrate)
        }
        .alert("Plus", isPresented: Binding(get: { plus.message != nil }, set: { if !$0 { plus.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(plus.message ?? "")
        }
        .accessibilityIdentifier("onboarding.plus")
    }

    private var header: some View {
        VStack(spacing: 10) {
            TempoMascot(size: 100, mood: plus.isActive ? .party : .happy, bounce: bounce, crowned: true)
                .scaleEffect(shown ? 1 : 0.4)
            HStack(spacing: 8) {
                Text(plus.isActive ? "Bienvenue dans" : "Passe à").font(.system(size: 30, weight: .heavy))
                PlusBadge(size: 30)
            }
            Text(plus.isActive ? "Tes avantages sont actifs. Profites-en !" : "Plus de jetons, plus de temps, plus de style.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // Bascule Annuel | Mensuel, comme Headspace.
    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach([PlusPeriod.annual, .monthly], id: \.self) { option in
                Button {
                    guard period != option else { return }
                    model.feedback?.play(.toggle)
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { period = option }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                        if option == .annual, let savings = plus.annualSavingsPercent {
                            Text("-\(savings) %")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(period == option ? Color.brandPink : Color(.systemGray4)))
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(period == option ? Color.white : Color.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background { if period == option { Capsule().fill(Color(white: 0.1)) } }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == option ? .isSelected : [])
                .accessibilityIdentifier("onboarding.plus.\(option.rawValue)")
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.systemGray6)))
    }

    // Frise : ce qui arrive aujourd'hui, à chaque renouvellement, et la résiliation.
    private var timeline: some View {
        let tokens = (period == .annual ? PlusRules.annualTokens : PlusRules.monthlyTokens).formatted()
        let entries: [(String, Color, String, String)] = [
            ("gift.fill", .brandPink, "Aujourd’hui", "Badge + à côté de ton nom et \(tokens) jetons offerts."),
            (
                "arrow.triangle.2.circlepath", .orange, period == .annual ? "Chaque année" : "Chaque mois",
                "Renouvellement automatique et \(tokens) nouveaux jetons."
            ),
            ("hand.wave.fill", .brandCyan, "Quand tu veux", "Résilie en deux touchers depuis les réglages de ton compte Apple."),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Image(systemName: entry.0)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(entry.1))
                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [entry.1.opacity(0.5), entries[index + 1].1.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(width: 4, height: 34)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.2).font(.headline)
                        Text(entry.3).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : 30)
                .animation(.spring(duration: 0.5).delay(0.15 + Double(index) * 0.1), value: shown)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
    }

    private var benefits: some View {
        let items: [(String, String)] = [
            ("🦄", "Cadeaux exclusifs"), ("🎬", "Vidéos de 10 min"), ("📡", "Lives de 4 h"), ("🎨", "Icônes de l’app"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(items[index].0).font(.title3)
                    Text(items[index].1).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemBackground)))
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
                .animation(.spring(duration: 0.45, bounce: 0.5).delay(0.45 + Double(index) * 0.07), value: shown)
            }
        }
    }

    private var activeCard: some View {
        Label("Abonnement activé", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(Color.brandPink)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if plus.isActive {
            Button("C’est parti !") { model.finish() }
                .buttonStyle(ChunkyButtonStyle())
                .accessibilityIdentifier("onboarding.plus.done")
        } else {
            Button {
                guard let selected else { return }
                Task { await plus.subscribe(selected) }
            } label: {
                switch plus.purchaseState {
                case .purchasing, .awaitingActivation, .restoring:
                    DotsLoader(size: 10, colors: (.white, .white.opacity(0.6)))
                case .idle:
                    Text(subscribeTitle)
                }
            }
            .buttonStyle(ChunkyButtonStyle())
            .disabled(selected == nil || plus.purchaseState != .idle)
            .accessibilityIdentifier("onboarding.plus.subscribe")
            if case .failed(let message) = plus.offersState {
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 24) {
                Button("Restaurer les achats") { Task { await plus.restore() } }
                    .disabled(plus.purchaseState != .idle)
                Button("Plus tard") { model.finish() }
                    .fontWeight(.bold)
                    .accessibilityIdentifier("onboarding.plus.later")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("Renouvellement automatique au prix affiché, jusqu’à l’annulation (au moins 24 h avant la fin de la période).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var subscribeTitle: String {
        guard let selected else { return "S’abonner" }
        return "S’abonner · \(selected.price) / \(selected.period == .annual ? "an" : "mois")"
    }
}
