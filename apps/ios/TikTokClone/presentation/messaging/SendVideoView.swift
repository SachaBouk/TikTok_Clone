import SwiftUI

// Choix des destinataires d'une vidéo envoyée par message : conversations récentes, puis abonnements.
// Chaque ligne a son bouton « Envoyer », qui devient « Envoyé ».
struct SendVideoView: View {
    @State private var viewModel: SendVideoViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SendVideoViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.recent.isEmpty {
                    Section("Récents") {
                        ForEach(viewModel.recent) { recipient in row(recipient) }
                    }
                }
                Section("Abonnements") {
                    ForEach(viewModel.others) { recipient in row(recipient) }
                    if viewModel.following.hasLoaded, viewModel.others.isEmpty {
                        Text(viewModel.recent.isEmpty ? "Suis des comptes pour leur envoyer des vidéos." : "Aucun autre abonnement.")
                            .foregroundStyle(.secondary)
                    } else if !viewModel.following.hasLoaded {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if viewModel.following.nextCursor != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear { Task { await viewModel.following.loadMore() } }
                    }
                }
            }
            .navigationTitle("Envoyer à")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .alert(
                "Envoi impossible",
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
    }

    private func row(_ recipient: SendVideoViewModel.Recipient) -> some View {
        HStack(spacing: 12) {
            UserRow(user: recipient.user)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch viewModel.deliveries[recipient.id] {
            case .sending:
                ProgressView()
            case .sent:
                Button("Envoyé") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
            case nil:
                Button("Envoyer") { Task { await viewModel.send(to: recipient) } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("sendVideo.send")
            }
        }
    }
}
