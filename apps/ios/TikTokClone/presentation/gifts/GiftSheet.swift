import SwiftUI

// Feuille de cadeaux (ADR-050), ouverte par le bouton 🎁 du lecteur : solde, « Recharger », catalogue, « Envoyer ».
struct GiftSheet: View {
    @State private var viewModel: GiftSheetViewModel
    let container: AppContainer
    let onSent: (GiftBurst) -> Void
    @State private var isShowingWallet = false
    @Environment(\.dismiss) private var dismiss

    init(viewModel: GiftSheetViewModel, container: AppContainer, onSent: @escaping (GiftBurst) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
        self.onSent = onSent
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                balanceBar
                content
                Spacer(minLength: 0)
                sendButton
            }
            .padding()
            .navigationTitle("Offrir un cadeau à @\(viewModel.target.recipient.username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isShowingWallet) {
                WalletView(source: .gift, container: container)
            }
        }
        .task { await viewModel.load() }
        // Retour du paywall : le solde a peut-être changé.
        .onChange(of: viewModel.balance) {
            if let selected = viewModel.selected { viewModel.select(selected) }
        }
        .alert(
            "Cadeau",
            isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var balanceBar: some View {
        HStack {
            Label {
                Text(viewModel.balance.map { "\($0.formatted()) jeton\($0 > 1 ? "s" : "")" } ?? "—")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.yellow)
            }
            .font(.headline)
            .accessibilityIdentifier("gift.balance")
            Spacer()
            Button("Recharger") { isShowingWallet = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("gift.topUp")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.catalogState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            ContentUnavailableView {
                Label("Cadeaux indisponibles", systemImage: "gift")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await viewModel.load() } }
            }
        case .loaded:
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.catalog) { item in
                    giftCell(item)
                }
            }
            if viewModel.needsTopUp {
                Label("Solde insuffisant pour ce cadeau.", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("gift.insufficient")
            }
        }
    }

    private func giftCell(_ item: GiftCatalogItem) -> some View {
        let isSelected = viewModel.selected == item
        return Button {
            viewModel.select(item)
        } label: {
            VStack(spacing: 6) {
                Text(item.info.emoji).font(.system(size: 40))
                Text(item.info.name).font(.subheadline.weight(.semibold))
                Text(item.priceLabel).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .opacity(viewModel.isAffordable(item) ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.info.name), \(item.priceLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("gift.item.\(item.info.code)")
    }

    @ViewBuilder
    private var sendButton: some View {
        if viewModel.needsTopUp {
            Button {
                isShowingWallet = true
            } label: {
                Label("Recharger des jetons", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button {
                Task {
                    if let burst = await viewModel.send() {
                        onSent(burst)
                        dismiss()
                    }
                }
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                    } else {
                        Text(viewModel.selected.map { "Envoyer \($0.info.label) · \($0.priceLabel)" } ?? "Choisis un cadeau")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("gift.send")
        }
    }
}

// Animation à l'envoi (ADR-050, choix du développeur : SwiftUI sobre, chez l'expéditeur) : l'emoji grossit et monte
// au-dessus de la vidéo, avec « Rose envoyée à @bob ».
struct GiftBurstView: View {
    let burst: GiftBurst
    @State private var isRising = false

    var body: some View {
        VStack(spacing: 12) {
            Text(burst.gift.emoji)
                .font(.system(size: 96))
                .scaleEffect(isRising ? 1.2 : 0.3)
                .shadow(radius: 12)
            Text(burst.caption)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .offset(y: isRising ? -120 : 80)
        .opacity(isRising ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.35)) { isRising = true }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gift.burst")
    }
}
