import SwiftUI

// Feuille de cadeaux (ADR-050), ouverte par le bouton 🎁 du lecteur ou d'un live, façon TikTok (ADR-066) : fond sombre,
// destinataire et solde en haut, catalogue sur 4 colonnes (cadeau choisi : « Envoyer » dans sa case, « Recharger »
// sans assez de jetons), « Cadeaux » et « Recharger › » en bas.
struct GiftSheet: View {
    @State private var viewModel: GiftSheetViewModel
    let container: AppContainer
    let onSent: (GiftBurst) -> Void
    @State private var isShowingWallet = false
    // Cadeau exclusif choisi sans abonnement : paywall « Plus » (ADR-073).
    @State private var isPresentingPlus = false
    @Environment(\.dismiss) private var dismiss

    init(viewModel: GiftSheetViewModel, container: AppContainer, onSent: @escaping (GiftBurst) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
        self.onSent = onSent
    }

    static let background = Color(red: 0.14, green: 0.14, blue: 0.14)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider().overlay(.white.opacity(0.12))
                ScrollView {
                    content
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                }
                bottomBar
            }
            .background(Self.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingWallet) {
                WalletView(source: .gift, container: container)
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(Self.background)
        .task { await viewModel.load() }
        .sheet(isPresented: $isPresentingPlus) { PlusSheet(source: .gift, container: container) }
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

    // Destinataire et solde ; × pour fermer.
    private var header: some View {
        let recipient = viewModel.target.recipient
        return HStack(spacing: 10) {
            AvatarView(url: recipient.avatarURL, name: recipient.displayName, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Offrir un cadeau à \(recipient.displayName)").font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    TokenCoin(size: 14)
                    Text(viewModel.balance.map { "\($0.formatted()) jeton\($0 > 1 ? "s" : "")" } ?? "—")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gift.balance")
            }
            Spacer()
            Button("Fermer", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
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
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.catalog) { item in
                    giftCell(item)
                }
            }
        }
    }

    // Case d'un cadeau : emoji, nom, prix ; choisie, fond plus sombre et « Envoyer » (ou « Recharger ») à la place du nom.
    private func giftCell(_ item: GiftCatalogItem) -> some View {
        let isSelected = viewModel.selected == item
        return VStack(spacing: 4) {
            Button {
                viewModel.select(item)
            } label: {
                VStack(spacing: 4) {
                    Text(item.info.emoji).font(.system(size: 50)).frame(height: 62)
                        .overlay(alignment: .topTrailing) {
                            // Cadeau exclusif des abonnés « Plus » (ADR-073).
                            if item.plusOnly { PlusBadge(size: 16).offset(x: 6, y: -2) }
                        }
                    if !isSelected {
                        Text(item.info.name).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    HStack(spacing: 3) {
                        TokenCoin(size: 13)
                        Text("\(item.price)").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, isSelected ? 4 : 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                item.plusOnly ? "\(item.info.name), \(item.priceLabel), réservé aux abonnés Plus" : "\(item.info.name), \(item.priceLabel)"
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("gift.item.\(item.info.code)")
            if isSelected { sendButton }
        }
        .background(isSelected ? Color.black.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }

    // « Envoyer » dans la case choisie ; « Recharger » si le solde ne suffit pas.
    @ViewBuilder
    private var sendButton: some View {
        if viewModel.selected?.plusOnly == true, !container.plus.isActive {
            Button {
                isPresentingPlus = true
            } label: {
                Text("Plus").font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.brandCyan, .brandPink], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 8)
            )
            .accessibilityLabel("Réservé aux abonnés Plus")
            .accessibilityIdentifier("gift.plusOnly")
        } else if viewModel.needsTopUp {
            Button {
                isShowingWallet = true
            } label: {
                Text("Recharger").font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("gift.insufficient")
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
                    if viewModel.isSending { ProgressView().tint(.white) } else { Text("Envoyer").font(.subheadline.bold()) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("gift.send")
        }
    }

    // « Cadeaux » à gauche, « Recharger › » à droite, comme TikTok.
    private var bottomBar: some View {
        HStack {
            Text("Cadeaux").font(.title3.weight(.semibold)).foregroundStyle(.white)
            Spacer()
            Button {
                isShowingWallet = true
            } label: {
                HStack(spacing: 8) {
                    TokenCoin(size: 22)
                    Text("Recharger").font(.title3.weight(.medium))
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gift.topUp")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
