import SwiftUI

// Feuille de signalement (ADR-038), ouverte depuis le « … » d'une vidéo, un commentaire ou le menu d'un profil.
// Après un signalement de compte, `onBlock` (s'il est fourni) propose de le bloquer.
struct ReportView: View {
    @State private var viewModel: ReportViewModel
    let onBlock: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ReportViewModel, onBlock: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onBlock = onBlock
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.state == .sent {
                    confirmation
                } else {
                    form
                }
            }
            .navigationTitle("Signaler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.state == .sent ? "Fermer" : "Annuler") { dismiss() }
                }
                if viewModel.state != .sent {
                    ToolbarItem(placement: .confirmationAction) {
                        if viewModel.state == .sending {
                            ProgressView()
                        } else {
                            Button("Envoyer") { Task { await viewModel.send() } }
                                .disabled(!viewModel.canSend)
                                .accessibilityIdentifier("report.send")
                        }
                    }
                }
            }
            .alert("Signalement", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(ReportReason.allCases) { reason in
                    Button {
                        viewModel.reason = reason
                    } label: {
                        HStack {
                            Text(reason.label)
                            Spacer()
                            if viewModel.reason == reason {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    // Texte des motifs en couleur normale (un bouton de Form prend sinon la couleur d'accent).
                    .tint(.primary)
                    .accessibilityAddTraits(viewModel.reason == reason ? .isSelected : [])
                    .accessibilityIdentifier("report.reason.\(reason.rawValue)")
                }
            } header: {
                Text(viewModel.target.question)
            } footer: {
                Text("Ton signalement est anonyme : la personne concernée ne saura pas qui l’a envoyé.")
            }
            Section {
                TextField("Ajoute des détails (facultatif)", text: $viewModel.details, axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                Text("\(viewModel.remainingCharacters)")
                    .foregroundStyle(viewModel.remainingCharacters < 0 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .disabled(viewModel.state == .sending)
    }

    private var confirmation: some View {
        ContentUnavailableView {
            Label("Merci", systemImage: "checkmark.shield")
        } description: {
            Text("Ton signalement sera examiné.")
        } actions: {
            if case .account(_, let username) = viewModel.target, let onBlock {
                Button("Bloquer @\(username)", role: .destructive) {
                    dismiss()
                    onBlock()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    // Feuille de signalement d'une cible ; en invité, l'appelant ouvre plutôt la connexion. `onDismiss` : après la
    // fermeture effective (une confirmation présentée pendant la fermeture serait ignorée).
    func reportSheet(
        _ target: Binding<ReportTarget?>,
        container: AppContainer,
        onBlock: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        sheet(item: target, onDismiss: onDismiss) { target in
            ReportView(viewModel: container.makeReportViewModel(target: target), onBlock: onBlock)
                .presentationDetents([.large])
        }
    }
}
