import SwiftUI

// Profil du compte connecté. Grilles, modification et historiques viendront à l'étape du profil.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @State private var isConfirmingSignOut = false

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                if let profile = viewModel.profile {
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(url: profile.avatarURL, name: profile.displayName, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName).font(.title3.bold())
                                Text("@\(profile.username)").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("profile.header")

                        if let bio = profile.bio {
                            Text(bio)
                        }
                    }

                    Section {
                        LabeledContent("Abonnés", value: profile.followersCount, format: .number)
                        LabeledContent("Abonnements", value: profile.followingCount, format: .number)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Profil")
            .refreshable { await viewModel.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            isConfirmingSignOut = true
                        }
                        .accessibilityIdentifier("profile.signOut")
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("profile.menu")
                }
            }
            .confirmationDialog("Se déconnecter ?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) {
                    Task { await viewModel.signOut() }
                }
            }
        }
    }
}
