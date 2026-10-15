import SwiftUI

// Réglages d'un chat de groupe (ADR-059), poussés depuis la conversation : nom (tout membre), membres (l'administrateur
// retire en glissant ; « Ajouter des membres » parmi ses amis), sourdine, supprimer pour soi, quitter le groupe.
struct GroupSettingsView: View {
    let viewModel: ConversationViewModel
    let container: AppContainer
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isAddingMembers = false
    @State private var removing: UserSummary?
    @State private var isConfirmingLeave = false
    @State private var isConfirmingDelete = false
    @State private var openedProfile: ProfileRoute?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let group = viewModel.group {
            content(group)
        } else {
            ProgressView()
        }
    }

    private func content(_ group: GroupChat) -> some View {
        let ownID = viewModel.ownID
        return List {
            Section {
                VStack(spacing: 8) {
                    ConversationAvatar(users: Array(group.others(ownID: ownID).prefix(2)), size: 88)
                    Text(group.title(ownID: ownID)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text(group.members.count > 1 ? "\(group.members.count) membres" : "1 membre").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                Button {
                    newName = group.name ?? ""
                    isRenaming = true
                } label: {
                    LabeledContent("Nom du groupe") {
                        Text(group.name ?? "Ajouter un nom").foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("groupSettings.name")
                Toggle(
                    "Mettre en sourdine",
                    isOn: Binding(
                        get: { group.muted },
                        set: { muted in Task { await viewModel.setMuted(muted) } }
                    )
                )
                .accessibilityIdentifier("groupSettings.mute")
            } footer: {
                Text("En sourdine, tu ne reçois plus de notification de ce groupe.")
            }
            Section {
                if GroupRules.remainingPlaces(members: group.members.count) > 0 {
                    Button("Ajouter des membres", systemImage: "person.badge.plus") { isAddingMembers = true }
                        .accessibilityIdentifier("groupSettings.addMembers")
                }
                ForEach(group.members) { member in
                    Button {
                        if member.user.id != ownID { openedProfile = ProfileRoute(username: member.user.username) }
                    } label: {
                        HStack(spacing: 12) {
                            UserRow(user: member.user)
                            Spacer()
                            if group.isAdmin(member.user.id) {
                                Text("Administrateur").font(.caption).foregroundStyle(.secondary)
                            } else if member.user.id == ownID {
                                Text("Toi").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if viewModel.isAdmin, member.user.id != ownID {
                            Button("Retirer", systemImage: "person.badge.minus", role: .destructive) { removing = member.user }
                        }
                    }
                    // Attachée à la ligne : posée sur tout l'écran, elle s'afficherait en popover dans un coin (iOS 26+).
                    .confirmationDialog(
                        "Retirer du groupe ?",
                        isPresented: Binding(
                            get: { removing?.id == member.user.id },
                            set: { if !$0 { removing = nil } }
                        ), titleVisibility: .visible
                    ) {
                        Button("Retirer", role: .destructive) { Task { await viewModel.removeMember(member.user) } }
                    } message: {
                        Text("\(member.user.displayName) ne verra plus les messages du groupe.")
                    }
                    .accessibilityIdentifier("groupSettings.member")
                }
            } header: {
                Text("Membres (\(group.members.count))")
            } footer: {
                if viewModel.isAdmin { Text("Tu es l’administrateur : glisse sur un membre pour le retirer.") }
            }
            Section {
                Button("Supprimer la conversation", role: .destructive) { isConfirmingDelete = true }
                    .confirmationDialog("Supprimer la conversation ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                        Button("Supprimer", role: .destructive) { Task { await viewModel.delete() } }
                    } message: {
                        Text("Les messages disparaissent pour toi seulement ; tu restes dans le groupe.")
                    }
                Button("Quitter le groupe", role: .destructive) { isConfirmingLeave = true }
                    .confirmationDialog("Quitter le groupe ?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                        Button("Quitter", role: .destructive) { Task { await viewModel.leave() } }
                    } message: {
                        Text("Tu ne recevras plus ses messages. Les tiens restent visibles des membres.")
                    }
                    .accessibilityIdentifier("groupSettings.leave")
            }
        }
        .navigationTitle("Réglages du groupe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedProfile) { route in
            ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
        }
        .alert("Nom du groupe", isPresented: $isRenaming) {
            TextField("Nom du groupe", text: $newName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { Task { await viewModel.rename(to: newName) } }
        } message: {
            Text("\(GroupRules.maxNameLength) caractères au plus. Sans nom, le groupe porte les noms de ses membres.")
        }
        .sheet(isPresented: $isAddingMembers) {
            if let conversationID = viewModel.conversationID {
                AddGroupMembersView(
                    model: container.makeFriendPicker(
                        .add(
                            conversationID: conversationID, members: Set(group.members.map(\.user.id)),
                            remaining: GroupRules.remainingPlaces(members: group.members.count)))
                ) { users in
                    await viewModel.addMembers(users)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        // Groupe quitté ou conversation supprimée : les réglages se ferment, puis la conversation (à sa réapparition).
        .onChange(of: viewModel.isClosed) { _, closed in
            if closed { dismiss() }
        }
        .accessibilityIdentifier("groupSettings")
    }
}
