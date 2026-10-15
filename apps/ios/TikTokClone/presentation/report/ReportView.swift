import SwiftUI

// Feuille de signalement (ADR-038), en étapes comme TikTok : « Choisis un motif » (liste à chevrons), puis la page du
// motif (explication, précision facultative, « Envoyer »), puis « Merci pour ton signalement ». Ouverte depuis la
// feuille de partage d'une vidéo, un commentaire, le menu d'un profil, un message, une story ou un live.
// Après l'envoi : « Bloquer @… » pour l'auteur d'une vidéo ou d'un commentaire (dans la feuille), ou pour un compte
// signalé depuis son profil (`onBlock`, confirmé par le profil une fois la feuille fermée).
struct ReportView: View {
    @State private var viewModel: ReportViewModel
    let onBlock: (() -> Void)?
    @State private var path: [ReportReason] = []
    @State private var isConfirmingBlock = false
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ReportViewModel, onBlock: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onBlock = onBlock
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.state == .sent {
                    thanks
                } else {
                    reasons
                }
            }
            .navigationTitle(viewModel.state == .sent ? "Signaler" : "Choisis un motif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeButton }
            .navigationDestination(for: ReportReason.self) { reason in
                details(reason)
                    .navigationTitle("Signaler")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { closeButton }
            }
        }
        // Envoyé depuis la page d'un motif : retour à la racine, qui affiche le remerciement.
        .onChange(of: viewModel.state) { _, state in
            if state == .sent { path = [] }
        }
        .alert(
            "Signalement",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Fermer", systemImage: "xmark") { dismiss() }
                .accessibilityIdentifier("report.close")
        }
    }

    // Étape 1 : les motifs, chacun ouvre sa page.
    private var reasons: some View {
        List {
            Section {
                ForEach(ReportReason.allCases) { reason in
                    NavigationLink(value: reason) {
                        Text(reason.label).font(.body.weight(.medium)).padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("report.reason.\(reason.rawValue)")
                }
            } header: {
                Text(viewModel.target.question)
            } footer: {
                Text(
                    ["Ton signalement est anonyme : la personne concernée ne saura pas qui l’a envoyé.", viewModel.target.privacyNote]
                        .compactMap { $0 }
                        .joined(separator: " ")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    // Étape 2 : le motif expliqué, une précision facultative, puis « Envoyer ».
    private func details(_ reason: ReportReason) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(reason.label).font(.title2.bold())
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                    Text(reason.explanation)
                }
                .foregroundStyle(.secondary)
                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Ajoute des détails (facultatif)", text: $viewModel.details, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("report.details")
                    Text("\(viewModel.remainingCharacters)")
                        .font(.caption)
                        .foregroundStyle(viewModel.remainingCharacters < 0 ? .red : .secondary)
                }
                if let note = viewModel.target.privacyNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.state == .sending)
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton(title: "Envoyer", isLoading: viewModel.state == .sending) {
                Task { await viewModel.send() }
            }
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("report.send")
        }
        .onAppear { viewModel.reason = reason }
    }

    // Étape 3 : remerciement, puis bloquer l'auteur si c'est possible.
    private var thanks: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white, .green)
                        .padding(.top, 40)
                    Text("Merci pour ton signalement").font(.title2.bold()).multilineTextAlignment(.center)
                    Text("Nous allons l’examiner. La décision arrivera dans ton activité.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let blockable = blockableUsername {
                        Divider().padding(.vertical, 8)
                        Text("Tu peux aussi :")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        blockRow(username: blockable)
                    }
                }
                .padding(.horizontal, 24)
            }
            PrimaryActionButton(title: "Terminé") { dismiss() }
                .accessibilityIdentifier("report.done")
        }
    }

    // Compte à bloquer : celui signalé depuis son profil, ou l'auteur du contenu signalé.
    private var blockableUsername: String? {
        if case .account(_, let username) = viewModel.target, onBlock != nil { return username }
        return viewModel.author?.username
    }

    @ViewBuilder
    private func blockRow(username: String) -> some View {
        HStack {
            Text(viewModel.blockState == .blocked ? "@\(username) est bloqué(e)" : "Bloquer @\(username)")
            Spacer()
            switch viewModel.blockState {
            case .idle:
                Button("Bloquer", role: .destructive) {
                    if let onBlock, viewModel.author == nil {
                        dismiss()
                        onBlock()
                    } else {
                        isConfirmingBlock = true
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("report.block")
                .confirmationDialog("Bloquer @\(username) ?", isPresented: $isConfirmingBlock, titleVisibility: .visible) {
                    Button("Bloquer", role: .destructive) { Task { await viewModel.blockAuthor() } }
                } message: {
                    Text("Vous ne pourrez plus vous suivre, réagir à vos vidéos ni vous écrire. Vos abonnements mutuels seront retirés.")
                }
            case .blocking:
                ProgressView()
            case .blocked:
                Image(systemName: "checkmark").foregroundStyle(.secondary)
            }
        }
    }
}

// Grand bouton rouge en bas d'une étape (« Envoyer », « Terminé »), comme TikTok.
struct PrimaryActionButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading { ProgressView().tint(.white) } else { Text(title).font(.headline) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.brandPink.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

extension View {
    // Feuille de signalement d'une cible ; en invité, l'appelant ouvre plutôt la connexion. `author` : auteur d'une vidéo
    // ou d'un commentaire, proposé au blocage après l'envoi. `onDismiss` : après la fermeture effective (une confirmation
    // présentée pendant la fermeture serait ignorée).
    func reportSheet(
        _ target: Binding<ReportTarget?>,
        container: AppContainer,
        author: UserSummary? = nil,
        onBlock: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        sheet(item: target, onDismiss: onDismiss) { target in
            ReportView(viewModel: container.makeReportViewModel(target: target, author: author), onBlock: onBlock)
                .presentationDetents([.large])
        }
    }
}
