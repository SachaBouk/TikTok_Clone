import SwiftUI

// Paywall et portefeuille (ADR-009, ADR-016) : solde, packs de jetons en vente (offre RevenueCat, prix du store),
// attente du crédit après un achat, historique des mouvements. Cadeaux (ADR-050) : gains reçus (non dépensables) et
// liste des cadeaux reçus.
struct WalletView: View {
    enum HistoryTab: Hashable {
        case movements, receivedGifts
    }

    let source: PaywallSource
    let container: AppContainer
    @Environment(AnalyticsModel.self) private var analytics
    @State private var history: PagedList<WalletTransaction>
    @State private var receivedGifts: PagedList<ReceivedGift>
    @State private var historyTab: HistoryTab = .movements

    init(source: PaywallSource, container: AppContainer) {
        self.source = source
        self.container = container
        _history = State(initialValue: container.makeWalletTransactionList())
        _receivedGifts = State(initialValue: container.makeReceivedGiftList())
    }

    private var wallet: WalletModel { container.wallet }

    var body: some View {
        List {
            balanceSection
            packsSection
            historySection
        }
        .navigationTitle("Jetons")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            analytics.track(.paywallViewed(source: source))
            async let balance: Void = wallet.refresh()
            async let packs: Void = wallet.loadPacks()
            async let transactions: Void = history.loadFirstIfNeeded()
            _ = await (balance, packs, transactions)
        }
        .refreshable {
            await wallet.refresh()
            await history.loadFirst()
            if historyTab == .receivedGifts { await receivedGifts.loadFirst() }
        }
        // Un crédit (achat, remboursement) ou un cadeau envoyé ajoute une ligne à l'historique.
        .onChange(of: wallet.balance) { old, new in
            if old != nil, new != old { Task { await history.loadFirst() } }
        }
        // Un cadeau reçu (ADR-050) ajoute une ligne aux cadeaux reçus.
        .onChange(of: wallet.earned) { old, new in
            if old != nil, new != old, receivedGifts.hasLoaded { Task { await receivedGifts.loadFirst() } }
        }
        .onChange(of: historyTab) { _, tab in
            if tab == .receivedGifts { Task { await receivedGifts.loadFirstIfNeeded() } }
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

    private var balanceSection: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow)
                Group {
                    if let balance = wallet.balance {
                        Text(balance, format: .number)
                    } else {
                        Text("—")
                    }
                }
                .font(.largeTitle.bold())
                .contentTransition(.numericText())
                .animation(.default, value: wallet.balance)
                .accessibilityIdentifier("wallet.balance")
                Text("jetons").foregroundStyle(.secondary)
                if let credit = wallet.lastCredit, credit > 0 {
                    Label("+\(credit) jetons ajoutés", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                        .accessibilityIdentifier("wallet.credited")
                }
                // Gains (ADR-050) : jetons reçus en cadeaux, à part du solde.
                if let earned = wallet.earned, earned > 0 {
                    Label("\(earned.formatted()) jeton\(earned > 1 ? "s" : "") reçu\(earned > 1 ? "s" : "") en cadeaux", systemImage: "gift.fill")
                        .font(.subheadline)
                        .foregroundStyle(.pink)
                        .padding(.top, 4)
                        .accessibilityIdentifier("wallet.earned")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var packsSection: some View {
        Section {
            if wallet.purchaseState == .awaitingCredit {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Achat confirmé, crédit en cours…")
                }
                .accessibilityIdentifier("wallet.awaitingCredit")
            }
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
                    packRow(pack)
                }
            }
        } header: {
            Text("Acheter des jetons")
        } footer: {
            Text("Paiement par l’App Store. Les jetons servent à offrir des cadeaux aux créateurs. Les jetons reçus en cadeaux ne se dépensent pas.")
        }
    }

    private func packRow(_ pack: TokenPack) -> some View {
        HStack {
            Label(pack.title, systemImage: "bitcoinsign.circle")
            Spacer()
            if wallet.purchaseState == .purchasing(pack.id) {
                ProgressView()
            } else {
                Button(pack.price) { Task { await wallet.buy(pack) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(wallet.purchaseState != .idle)
                    .accessibilityIdentifier("wallet.buy.\(pack.productID)")
            }
        }
    }

    private var historySection: some View {
        Section {
            Picker("Historique", selection: $historyTab) {
                Text("Mouvements").tag(HistoryTab.movements)
                Text("Cadeaux reçus").tag(HistoryTab.receivedGifts)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("wallet.historyTabs")
            switch historyTab {
            case .movements:
                placeholder(history.state, isEmpty: history.items.isEmpty, empty: "Aucun mouvement pour le moment.")
                ForEach(history.items) { transaction in
                    WalletTransactionRow(transaction: transaction)
                        .onAppear { Task { await history.loadMore(ifNeededAfter: transaction) } }
                }
            case .receivedGifts:
                placeholder(receivedGifts.state, isEmpty: receivedGifts.items.isEmpty, empty: "Aucun cadeau reçu pour le moment.")
                ForEach(receivedGifts.items) { gift in
                    ReceivedGiftRow(gift: gift)
                        .onAppear { Task { await receivedGifts.loadMore(ifNeededAfter: gift) } }
                }
            }
        } header: {
            Text("Historique")
        }
    }

    @ViewBuilder
    private func placeholder(_ state: PagedListState, isEmpty: Bool, empty: String) -> some View {
        if isEmpty {
            switch state {
            case .idle, .loading: ProgressView().frame(maxWidth: .infinity)
            case .failed(let message): Text(message).foregroundStyle(.secondary)
            case .loaded: Text(empty).foregroundStyle(.secondary)
            }
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
