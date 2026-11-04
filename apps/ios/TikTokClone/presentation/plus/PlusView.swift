import SwiftUI

// Badge « + » des abonnés « Plus » (ADR-073), à côté du nom : profil, vidéos, commentaires, messages, lives, listes.
struct PlusBadge: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: size * 0.62, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [.brandCyan, .brandPink], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityLabel("Abonné Plus")
    }
}

extension View {
    // Nom suivi du badge si le compte est abonné.
    func plusBadge(_ isPlus: Bool, size: CGFloat = 16) -> some View {
        HStack(spacing: 4) {
            self
            if isPlus { PlusBadge(size: size) }
        }
    }
}

// Paywall « Plus » (ADR-073) : avantages, choix Annuel | Mensuel (prix du store, économie de l'annuel), « S'abonner »,
// « Restaurer les achats » et conditions du renouvellement automatique (exigés par Apple). Abonné : échéance,
// « Gérer l'abonnement » et icônes de l'app. Poussé depuis le menu ☰, ou présenté depuis un avantage verrouillé.
struct PlusView: View {
    let source: PlusPaywallSource
    let container: AppContainer
    @Environment(AnalyticsModel.self) private var analytics
    @State private var selectedOfferID: PlusOffer.ID?
    @State private var isShowingIcons = false

    private var plus: PlusModel { container.plus }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                benefits
                if plus.isActive {
                    subscriberCard
                } else {
                    offers
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            if !plus.isActive { subscribeBar }
        }
        .background { PlusBackground() }
        .navigationTitle("Plus")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingIcons) { AppIconSettingsView(container: container) }
        .task {
            analytics.track(.plusPaywallViewed(source: source))
            async let status: Void = plus.refresh()
            async let offers: Void = plus.loadOffers()
            _ = await (status, offers)
            if selectedOfferID == nil { selectedOfferID = plus.offers.first?.id }
        }
        .onChange(of: plus.offers) { _, offers in
            if selectedOfferID == nil || !offers.contains(where: { $0.id == selectedOfferID }) { selectedOfferID = offers.first?.id }
        }
        .alert(
            "Plus",
            isPresented: Binding(get: { plus.message != nil }, set: { if !$0 { plus.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(plus.message ?? "")
        }
        .accessibilityIdentifier("plus")
    }

    private var header: some View {
        VStack(spacing: 12) {
            AppLogo(size: 64, foreground: .primary)
            HStack(spacing: 8) {
                Text("TikTok Clone").font(.title.weight(.heavy))
                PlusBadge(size: 30)
            }
            Text(plus.justActivated ? "Bienvenue dans Plus ! Tes avantages sont actifs." : "Plus d’avantages, sans rien retirer aux autres.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            benefit("plus.circle.fill", "Badge « + »", "À côté de ton nom, partout dans l’app.")
            benefit(
                "bitcoinsign.circle.fill", "Jetons offerts",
                "\(PlusRules.monthlyTokens) jetons par mois (\(PlusRules.annualTokens) d’un coup avec l’annuel).")
            benefit("gift.fill", "Cadeaux exclusifs", "🦄 Licorne et 🪐 Planète, sur les vidéos et dans les lives.")
            benefit("film.stack.fill", "Vidéos et lives plus longs", "Vidéos de 10 minutes, lives de 4 heures.")
            benefit("app.badge.fill", "Icônes de l’app", "Or, Néon ou Rétro, au choix.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func benefit(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.brandPink)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var offers: some View {
        switch plus.offersState {
        case .idle, .loading:
            DotsLoader().frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .loaded:
            VStack(spacing: 12) {
                ForEach(plus.offers) { offer in
                    offerCard(offer)
                }
            }
        }
    }

    private func offerCard(_ offer: PlusOffer) -> some View {
        let isSelected = offer.id == selectedOfferID
        return Button {
            selectedOfferID = offer.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.brandPink : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(offer.period.title).font(.headline)
                        if offer.period == .annual, let savings = plus.annualSavingsPercent {
                            Text("-\(savings) %")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.brandPink, in: Capsule())
                        }
                    }
                    if let perMonth = offer.pricePerMonth {
                        Text("Soit \(perMonth) par mois").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(offer.period == .annual ? "\(offer.price) / an" : "\(offer.price) / mois").font(.headline)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPink : Color(.separator), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("plus.offer.\(offer.period.rawValue)")
    }

    private var subscribeBar: some View {
        let selected = plus.offers.first { $0.id == selectedOfferID }
        return VStack(spacing: 10) {
            Button {
                guard let selected else { return }
                Task { await plus.subscribe(selected) }
            } label: {
                Group {
                    switch plus.purchaseState {
                    case .purchasing, .awaitingActivation, .restoring: DotsLoader(colors: (.white, .white))
                    case .idle: Text("S’abonner").font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.brandPink, in: Capsule())
            }
            .disabled(selected == nil || plus.purchaseState != .idle)
            .accessibilityIdentifier("plus.subscribe")
            Button("Restaurer les achats") { Task { await plus.restore() } }
                .font(.subheadline)
                .disabled(plus.purchaseState != .idle)
                .accessibilityIdentifier("plus.restore")
            Text(
                "Abonnement à renouvellement automatique, au prix affiché, jusqu’à son annulation. Annule à tout moment dans les réglages de ton compte Apple, au moins 24 h avant la fin de la période en cours."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var subscriberCard: some View {
        VStack(spacing: 14) {
            Label("Tu es abonné(e) à Plus", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.brandPink)
            if let status = plus.status, let expiresAt = status.expiresAt {
                let date = expiresAt.formatted(.dateTime.day().month(.wide).year())
                Text(status.willRenew == false ? "Se termine le \(date)" : "Renouvellement le \(date)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let period = status.period { Text("Formule \(period.title.lowercased())").font(.subheadline).foregroundStyle(.secondary) }
            }
            Button("Changer l’icône de l’app") { isShowingIcons = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("plus.icons")
            Button("Gérer l’abonnement") { Task { await plus.manageSubscription() } }
                .font(.subheadline)
                .accessibilityIdentifier("plus.manage")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// Fond du paywall : dégradé cyan et rose très doux, comme la page « Solde ».
private struct PlusBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.brandCyan.opacity(0.18), Color(.systemGroupedBackground), Color.brandPink.opacity(0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// Paywall présenté depuis un avantage verrouillé (cadeau exclusif, vidéo trop longue, icônes) : feuille avec sa pile.
struct PlusSheet: View {
    let source: PlusPaywallSource
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlusView(source: source, container: container)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .environment(container.analytics)
    }
}
