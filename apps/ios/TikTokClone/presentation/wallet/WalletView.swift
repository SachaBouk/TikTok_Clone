import SwiftUI

// Paywall et portefeuille (ADR-009, ADR-016) : solde, packs de jetons en vente (offre RevenueCat, prix du store),
// attente du crédit après un achat, historique des mouvements.
struct WalletView: View {
    let source: PaywallSource
    let container: AppContainer
    @Environment(AnalyticsModel.self) private var analytics
    @State private var history: PagedList<WalletTransaction>

    init(source: PaywallSource, container: AppContainer) {
        self.source = source
        self.container = container
        _history = State(initialValue: container.makeWalletTransactionList())
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
        }
        // Un crédit (achat, remboursement) ajoute une ligne à l'historique.
        .onChange(of: wallet.balance) { old, new in
            if old != nil, new != old { Task { await history.loadFirst() } }
        }
        .alert("Jetons", isPresented: Binding(
            get: { wallet.message != nil },
            set: { if !$0 { wallet.message = nil } }
        )) {
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
            Text("Paiement par l’App Store. Les jetons serviront bientôt à envoyer des cadeaux.")
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
        Section("Historique") {
            if history.items.isEmpty {
                switch history.state {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity)
                case .failed(let message): Text(message).foregroundStyle(.secondary)
                case .loaded: Text("Aucun mouvement pour le moment.").foregroundStyle(.secondary)
                }
            }
            ForEach(history.items) { transaction in
                WalletTransactionRow(transaction: transaction)
                    .onAppear { Task { await history.loadMore(ifNeededAfter: transaction) } }
            }
        }
    }
}

private struct WalletTransactionRow: View {
    let transaction: WalletTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.kind.title)
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
}
