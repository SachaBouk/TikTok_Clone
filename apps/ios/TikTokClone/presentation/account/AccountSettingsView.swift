import Observation
import SwiftUI

// Paramètres du compte : portefeuille, historiques, comptes bloqués, déconnexion, suppression du compte (exigence Apple).
@MainActor
@Observable
final class AccountSettingsViewModel {
    var errorMessage: String?
    private(set) var isDeleting = false

    private let deleteAccount: DeleteAccountUseCase
    private let discardUploads: DiscardUploadsUseCase
    private let session: SessionStore

    init(deleteAccount: DeleteAccountUseCase, discardUploads: DiscardUploadsUseCase, session: SessionStore) {
        self.deleteAccount = deleteAccount
        self.discardUploads = discardUploads
        self.session = session
    }

    var username: String? { session.profile?.username }

    func signOut() async {
        await session.signOut()
    }

    // Suppression définitive : l'app repasse en invité ; les envois de vidéos en attente sont oubliés.
    func deleteMyAccount() async {
        guard let me = session.profile, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deleteAccount()
            discardUploads(userID: me.id)
            session.accountDeleted()
        } catch {
            let error = AppError.from(error)
            if error == .sessionExpired {
                session.sessionExpired()
            } else {
                errorMessage = error.message
            }
        }
    }
}

struct AccountSettingsView: View {
    let wallet: WalletModel
    @State private var viewModel: AccountSettingsViewModel
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDeletion = false

    init(viewModel: AccountSettingsViewModel, wallet: WalletModel) {
        _viewModel = State(initialValue: viewModel)
        self.wallet = wallet
    }

    var body: some View {
        List {
            Section("Portefeuille") {
                NavigationLink(value: AccountRoute.wallet(.settings)) {
                    LabeledContent {
                        if let balance = wallet.balance { Text(balance, format: .number) }
                    } label: {
                        Label("Jetons", systemImage: "bitcoinsign.circle")
                    }
                }
                .accessibilityIdentifier("settings.wallet")
            }
            Section("Activité") {
                NavigationLink(value: AccountRoute.viewHistory) {
                    Label("Historique de visionnage", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("settings.viewHistory")
                NavigationLink(value: AccountRoute.commentHistory) {
                    Label("Historique des commentaires", systemImage: "text.bubble")
                }
                .accessibilityIdentifier("settings.commentHistory")
            }
            Section {
                NavigationLink(value: AccountRoute.blockedAccounts) {
                    Label("Comptes bloqués", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.blocked")
                AnalyticsConsentToggle()
            } header: {
                Text("Confidentialité")
            } footer: {
                Text(
                    "Mesure d’audience : vidéos regardées, réactions et inscription, avec PostHog (Union européenne), sous le seul identifiant de ton compte."
                )
            }
            Section {
                Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right") { isConfirmingSignOut = true }
                    .accessibilityIdentifier("profile.signOut")
                    // Attachée au bouton : iOS ancre la confirmation sur la vue qui la porte (sur la liste entière,
                    // elle apparaissait en haut de l'écran, loin du bouton touché).
                    .confirmationDialog("Se déconnecter ?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                        Button("Se déconnecter", role: .destructive) { Task { await viewModel.signOut() } }
                    }
            }
            Section {
                Button("Supprimer le compte", systemImage: "trash", role: .destructive) { isConfirmingDeletion = true }
                    .disabled(viewModel.isDeleting)
                    .accessibilityIdentifier("settings.deleteAccount")
            } footer: {
                Text("La suppression est immédiate et définitive.")
            }
        }
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isDeleting { ProgressView() }
        }
        .alert("Supprimer ton compte ?", isPresented: $isConfirmingDeletion) {
            Button("Supprimer définitivement", role: .destructive) { Task { await viewModel.deleteMyAccount() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Ton compte @\(viewModel.username ?? "") sera supprimé tout de suite, avec tes vidéos, tes commentaires, tes messages, tes abonnés et tes abonnements. Cette action est irréversible."
            )
        }
        .alert(
            "Paramètres",
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
