import SwiftUI

// Page « Solde », comme TikTok (ADR-057 ; portefeuille de l'ADR-009, cadeaux de l'ADR-050) : en grand les gains
// (jetons reçus en cadeaux, non dépensables), qu'un œil masque ; pastille « Jetons N | Obtenir des jetons », qui
// ouvre les packs en vente (offre RevenueCat, prix du store) ; « Transactions » et « Cadeaux reçus » sur leurs pages.
// Ouverte depuis le bouton jetons du profil ou « Recharger » d'un cadeau, elle ouvre d'emblée les packs.
struct WalletView: View {
    let source: PaywallSource
    let container: AppContainer
    @Environment(AnalyticsModel.self) private var analytics
    @AppStorage("walletAmountsHidden") private var isHidingAmounts = false
    @State private var isPresentingPacks = false
    @State private var isShowingTransactions = false
    @State private var isShowingReceivedGifts = false
    @State private var didOpenPacks = false

    private var wallet: WalletModel { container.wallet }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                earnings
                tokensPill
                transactionsCard
                creditStatus
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Text("Les jetons ne sont pas un produit financier. Les jetons reçus en cadeaux ne se dépensent pas et ne se convertissent pas en argent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .background { WalletBackground() }
        .navigationTitle("Solde")
        .navigationBarTitleDisplayMode(.inline)
        // Boutons plutôt que `NavigationLink(value:)` : la page est aussi poussée dans la feuille de cadeaux, dont la
        // pile n'a pas les destinations de l'app.
        .navigationDestination(isPresented: $isShowingTransactions) { WalletTransactionsView(container: container) }
        .navigationDestination(isPresented: $isShowingReceivedGifts) { ReceivedGiftsView(container: container) }
        .sheet(isPresented: $isPresentingPacks) { TokenPacksSheet(wallet: wallet) }
        .task {
            analytics.track(.paywallViewed(source: source))
            if source != .menu, !didOpenPacks {
                didOpenPacks = true
                isPresentingPacks = true
            }
            async let balance: Void = wallet.refresh()
            async let packs: Void = wallet.loadPacks()
            _ = await (balance, packs)
        }
        .refreshable { await wallet.refresh() }
        .alert(
            "Jetons",
            isPresented: Binding(
                get: { wallet.message != nil && !isPresentingPacks },
                set: { if !$0 { wallet.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wallet.message ?? "")
        }
    }

    // Gains (ADR-050), en grand ; le chevron ouvre les cadeaux reçus.
    private var earnings: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Gains en jetons")
                Button {
                    isHidingAmounts.toggle()
                } label: {
                    Image(systemName: isHidingAmounts ? "eye.slash" : "eye")
                }
                .accessibilityLabel(isHidingAmounts ? "Afficher les montants" : "Masquer les montants")
                .accessibilityIdentifier("wallet.toggleAmounts")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            Button {
                isShowingReceivedGifts = true
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    amount(wallet.earned)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.default, value: wallet.earned)
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cadeaux reçus")
            .accessibilityIdentifier("wallet.earned")
        }
    }

    // Jetons achetés (solde dépensable) et achat de packs.
    private var tokensPill: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                TokenCoin()
                Text("Jetons").foregroundStyle(.secondary)
                amount(wallet.balance)
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                    .animation(.default, value: wallet.balance)
                    .accessibilityIdentifier("wallet.balance")
            }
            Divider().frame(height: 20)
            Button {
                isPresentingPacks = true
            } label: {
                Label("Obtenir des jetons", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wallet.getTokens")
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.background.opacity(0.6), in: Capsule())
        .overlay { Capsule().strokeBorder(.background, lineWidth: 1) }
    }

    private var transactionsCard: some View {
        Button {
            isShowingTransactions = true
        } label: {
            HStack {
                Text("Transactions").font(.title3.bold())
                Spacer()
                Text("Tout voir").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wallet.transactions")
    }

    // Après un achat : crédit en attente, puis « +N jetons ajoutés ».
    @ViewBuilder
    private var creditStatus: some View {
        if wallet.purchaseState == .awaitingCredit {
            HStack(spacing: 12) {
                ProgressView()
                Text("Achat confirmé, crédit en cours…")
            }
            .accessibilityIdentifier("wallet.awaitingCredit")
        } else if let credit = wallet.lastCredit, credit > 0 {
            Label("+\(credit) jetons ajoutés", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("wallet.credited")
        }
    }

    @ViewBuilder
    private func amount(_ value: Int?) -> some View {
        if isHidingAmounts {
            Text("••••")
        } else if let value {
            Text(value, format: .number)
        } else {
            Text("—")
        }
    }
}

// Dégradé cyan et rose en haut de la page, comme celle de TikTok.
private struct WalletBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [.cyan.opacity(0.3), .pink.opacity(0.08), .pink.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 360)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

// Pièce jaune des jetons.
struct TokenCoin: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "bitcoinsign.circle.fill")
            .resizable()
            .frame(width: size, height: size)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .orange)
            .accessibilityHidden(true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

// Packs de jetons en vente (offre courante RevenueCat, titre et prix du store), dans une feuille.
private struct TokenPacksSheet: View {
    let wallet: WalletModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if wallet.purchaseState == .awaitingCredit {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Achat confirmé, crédit en cours…")
                        }
                    } else if let credit = wallet.lastCredit, credit > 0 {
                        Label("+\(credit) jetons ajoutés", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    packs
                } footer: {
                    Text("Paiement par l’App Store. Les jetons servent à offrir des cadeaux aux créateurs.")
                }
            }
            .navigationTitle("Obtenir des jetons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        TokenCoin(size: 18)
                        if let balance = wallet.balance {
                            Text(balance, format: .number).font(.headline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Solde : \(wallet.balance ?? 0) jetons")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .alert(
                "Jetons",
                isPresented: Binding(
                    get: { wallet.message != nil },
                    set: { if !$0 { wallet.message = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(wallet.message ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var packs: some View {
        switch wallet.packsState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.secondary)
                if wallet.isPurchaseAvailable {
                    Button("Réessayer") { Task { await wallet.loadPacks() } }
                }
            }
            .accessibilityIdentifier("wallet.packsUnavailable")
        case .loaded:
            if wallet.packs.isEmpty {
                Text("Aucun pack en vente pour le moment.").foregroundStyle(.secondary)
            }
            ForEach(wallet.packs) { pack in
                HStack {
                    Label {
                        Text(pack.title)
                    } icon: {
                        TokenCoin()
                    }
                    Spacer()
                    if wallet.purchaseState == .purchasing(pack.id) {
                        ProgressView()
                    } else {
                        Button(pack.price) { Task { await wallet.buy(pack) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.brandPink)
                            .disabled(wallet.purchaseState != .idle)
                            .accessibilityIdentifier("wallet.buy.\(pack.productID)")
                    }
                }
            }
        }
    }
}

// « Transactions » (« Tout voir ») : mouvements de jetons, achats et cadeaux envoyés, du plus récent au plus ancien.
struct WalletTransactionsView: View {
    let container: AppContainer
    @State private var list: PagedList<WalletTransaction>

    init(container: AppContainer) {
        self.container = container
        _list = State(initialValue: container.makeWalletTransactionList())
    }

    var body: some View {
        List {
            ForEach(list.items) { transaction in
                WalletTransactionRow(transaction: transaction)
                    .onAppear { Task { await list.loadMore(ifNeededAfter: transaction) } }
            }
        }
        .overlay {
            PagedListPlaceholder(
                state: list.state, isEmpty: list.items.isEmpty, emptyTitle: "Aucun mouvement pour le moment",
                emptySystemImage: "list.bullet.rectangle"
            ) { await list.loadFirst() }
        }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await list.loadFirstIfNeeded() }
        .refreshable { await list.loadFirst() }
        // Un crédit (achat, remboursement) ou un cadeau envoyé ajoute une ligne.
        .onChange(of: container.wallet.balance) { old, new in
            if old != nil, new != old { Task { await list.loadFirst() } }
        }
    }
}

// Cadeaux reçus (ADR-050), ouverts par les gains de la page « Solde ».
struct ReceivedGiftsView: View {
    let container: AppContainer
    @State private var list: PagedList<ReceivedGift>

    init(container: AppContainer) {
        self.container = container
        _list = State(initialValue: container.makeReceivedGiftList())
    }

    var body: some View {
        List {
            ForEach(list.items) { gift in
                ReceivedGiftRow(gift: gift)
                    .onAppear { Task { await list.loadMore(ifNeededAfter: gift) } }
            }
        }
        .overlay {
            PagedListPlaceholder(
                state: list.state, isEmpty: list.items.isEmpty, emptyTitle: "Aucun cadeau reçu pour le moment", emptySystemImage: "gift"
            ) { await list.loadFirst() }
        }
        .navigationTitle("Cadeaux reçus")
        .navigationBarTitleDisplayMode(.inline)
        .task { await list.loadFirstIfNeeded() }
        .refreshable { await list.loadFirst() }
        .onChange(of: container.wallet.earned) { old, new in
            if old != nil, new != old { Task { await list.loadFirst() } }
        }
    }
}

// Cadeau reçu (ADR-050) : expéditeur, cadeau, gains ajoutés.
private struct ReceivedGiftRow: View {
    let gift: ReceivedGift

    var body: some View {
        HStack(spacing: 12) {
            Text(gift.gift.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(gift.gift.name) de \(gift.sender.map { "@\($0.username)" } ?? "un compte supprimé")")
                Text(gift.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(gift.amount, format: .number.sign(strategy: .always()))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.pink)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WalletTransactionRow: View {
    let transaction: WalletTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(transaction.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount, format: .number.sign(strategy: .always()))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(transaction.amount >= 0 ? .green : .red)
        }
        .accessibilityElement(children: .combine)
    }

    // Cadeau envoyé : « 🌹 Rose à @bob ».
    private var title: String {
        guard transaction.kind == .giftSent, let gift = transaction.gift else { return transaction.kind.title }
        return "\(gift.label) à \(transaction.recipient.map { "@\($0.username)" } ?? "un compte supprimé")"
    }
}
