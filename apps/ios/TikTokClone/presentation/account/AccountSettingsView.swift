import Observation
import SwiftUI

// Paramètres du compte : déconnexion, suppression du compte (exigence Apple).
@MainActor
@Observable
final class AccountSettingsViewModel {
    var errorMessage: String?
    private(set) var isDeleting = false

    private(set) var isSavingVisibility = false

    private let deleteAccount: DeleteAccountUseCase
    private let discardUploads: DiscardUploadsUseCase
    private let setListVisibility: SetReactionListVisibilityUseCase?
    private let session: SessionStore

    init(
        deleteAccount: DeleteAccountUseCase, discardUploads: DiscardUploadsUseCase,
        setListVisibility: SetReactionListVisibilityUseCase? = nil, session: SessionStore
    ) {
        self.deleteAccount = deleteAccount
        self.discardUploads = discardUploads
        self.setListVisibility = setListVisibility
        self.session = session
    }

    var username: String? { session.profile?.username }

    // Qui voit ses vidéos aimées ou ses favoris (ADR-071) ; privés tant que le profil n'est pas chargé.
    func visibility(of grid: ProfileGrid) -> VideoVisibility {
        session.profile.map { $0.isPrivate(grid) ? .onlyMe : .everyone } ?? .onlyMe
    }

    // Enregistré aussitôt ; le profil de la session suit (son profil, ses paramètres).
    func setVisibility(_ visibility: VideoVisibility, of grid: ProfileGrid) async {
        guard let setListVisibility, !isSavingVisibility, visibility != self.visibility(of: grid) else { return }
        isSavingVisibility = true
        defer { isSavingVisibility = false }
        do {
            session.update(try await setListVisibility(visibility, of: grid))
        } catch {
            let error = AppError.from(error)
            if error == .sessionExpired {
                session.sessionExpired()
            } else {
                errorMessage = error.message
            }
        }
    }

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

// « Paramètres et confidentialité », comme TikTok (ADR-057) : sections Activité, Compte, Visibilité, Confidentialité,
// Connexion. Hors périmètre : compte privé, notifications, temps d'écran, Connexion Famille, mentions, réutilisation
// du contenu, téléchargements, changement de compte.
struct AccountSettingsView: View {
    @State private var viewModel: AccountSettingsViewModel
    @State private var isConfirmingSignOut = false

    init(viewModel: AccountSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            // Grand titre sur deux lignes, comme TikTok (le grand titre de la barre serait tronqué).
            Text("Paramètres et confidentialité")
                .font(.largeTitle.bold())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
                .accessibilityAddTraits(.isHeader)
            Section("Activité") {
                // Choisis à l'inscription (ADR-055), modifiables ici.
                NavigationLink(value: AccountRoute.interests) {
                    Label("Centres d’intérêt", systemImage: "heart.text.square.fill")
                }
                .accessibilityIdentifier("settings.interests")
                // Icônes au choix des abonnés « Plus » (ADR-073).
                NavigationLink(value: AccountRoute.appIcon) {
                    Label("Icône de l’app", systemImage: "app.badge.fill")
                }
                .accessibilityIdentifier("settings.appIcon")
                // Tutoriels de l'onboarding animé (ADR-075).
                NavigationLink(value: AccountRoute.tutorialReplay) {
                    Label("Revoir la présentation", systemImage: "sparkles.rectangle.stack.fill")
                }
                .accessibilityIdentifier("settings.tutorialReplay")
            }
            Section("Compte") {
                NavigationLink(value: AccountRoute.account) {
                    Label("Compte", systemImage: "person.fill")
                }
                .accessibilityIdentifier("settings.account")
                if let username = viewModel.username {
                    ShareLink(item: ProfileLink.url(for: username), message: Text("Mon profil sur TikTok Clone")) {
                        Label("Partager le profil", systemImage: "arrowshape.turn.up.right.fill")
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("settings.shareProfile")
                }
            }
            Section("Visibilité") {
                NavigationLink(value: AccountRoute.blockedAccounts) {
                    Label("Comptes bloqués", systemImage: "nosign")
                }
                .accessibilityIdentifier("settings.blocked")
                // Qui voit ses vidéos aimées et ses favoris (ADR-071), chacun sur sa page.
                ForEach([ProfileGrid.likes, .favorites], id: \.self) { grid in
                    NavigationLink(value: AccountRoute.listVisibility(grid)) {
                        LabeledContent {
                            Text(viewModel.visibility(of: grid).label)
                        } label: {
                            Label {
                                Text(ReactionListVisibilityView.title(grid))
                            } icon: {
                                // Dans un `LabeledContent`, l'icône prendrait la teinte de l'app.
                                Image(systemName: grid == .likes ? "heart.fill" : "bookmark.fill").foregroundStyle(Color(.systemGray))
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.\(grid.rawValue)Visibility")
                }
            }
            Section {
                AnalyticsConsentToggle()
            } header: {
                Text("Confidentialité")
            } footer: {
                Text(
                    "Mesure d’audience : vidéos regardées, réactions et inscription, avec PostHog (Union européenne), sous le seul identifiant de ton compte."
                )
            }
            Section("Connexion") {
                Button {
                    isConfirmingSignOut = true
                } label: {
                    Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("profile.signOut")
                // Attachée au bouton : iOS ancre la confirmation sur la vue qui la porte.
                .confirmationDialog("Se déconnecter ?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                    Button("Se déconnecter", role: .destructive) { Task { await viewModel.signOut() } }
                }
            }
        }
        .labelStyle(SettingsLabelStyle())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Page « Compte » : pseudo, suppression du compte.
struct AccountDetailsView: View {
    @State private var viewModel: AccountSettingsViewModel
    @State private var isConfirmingDeletion = false

    init(viewModel: AccountSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section("Informations du compte") {
                LabeledContent {
                    Text("@\(viewModel.username ?? "")")
                } label: {
                    Label {
                        Text("Nom d’utilisateur")
                    } icon: {
                        Image(systemName: "at").foregroundStyle(Color(.systemGray))
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("Supprimer le compte", systemImage: "trash.fill")
                }
                .foregroundStyle(.red)
                .disabled(viewModel.isDeleting)
                .accessibilityIdentifier("settings.deleteAccount")
            } footer: {
                Text("La suppression est immédiate et définitive.")
            }
        }
        .labelStyle(SettingsLabelStyle())
        .navigationTitle("Compte")
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
            "Compte",
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

// Ligne de réglages comme TikTok : icône grise pleine, puis le titre.
struct SettingsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
                .foregroundStyle(Color(.systemGray))
                .frame(width: 26)
            configuration.title
                .font(.body.weight(.medium))
        }
    }
}

// « Vidéos aimées » ou « Vidéos favorites » (ADR-071) : « Tout le monde » ou « Toi uniquement », enregistré au toucher.
struct ReactionListVisibilityView: View {
    let grid: ProfileGrid
    @State var viewModel: AccountSettingsViewModel

    static func title(_ grid: ProfileGrid) -> String {
        grid == .likes ? "Vidéos aimées" : "Vidéos favorites"
    }

    var body: some View {
        List {
            Section {
                ForEach(VideoVisibility.allCases, id: \.self) { visibility in
                    Button {
                        Task { await viewModel.setVisibility(visibility, of: grid) }
                    } label: {
                        HStack {
                            Text(visibility.label).foregroundStyle(.primary)
                            Spacer()
                            if viewModel.visibility(of: grid) == visibility {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.brandPink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(viewModel.isSavingVisibility)
                    .accessibilityAddTraits(viewModel.visibility(of: grid) == visibility ? .isSelected : [])
                    .accessibilityIdentifier("listVisibility.\(visibility.rawValue)")
                }
            } header: {
                Text(grid == .likes ? "Qui peut voir les vidéos que tu aimes" : "Qui peut voir tes vidéos favorites")
            } footer: {
                Text(
                    grid == .likes
                        ? "« Tout le monde » : l'onglet ♡ de ton profil est visible des autres. Les vidéos privées n'y apparaissent jamais."
                        : "« Tout le monde » : l'onglet des favoris de ton profil est visible des autres. Les vidéos privées n'y apparaissent jamais."
                )
            }
        }
        // La teinte de l'app colorerait le texte des boutons (piège rencontré).
        .tint(.primary)
        .navigationTitle(Self.title(grid))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            Self.title(grid),
            isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
