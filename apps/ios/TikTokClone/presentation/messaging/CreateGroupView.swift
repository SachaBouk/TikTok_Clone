import SwiftUI

// « Créer un chat de groupe », comme TikTok (ADR-059) : type Privé (« Pour les amis » ; le type Public est reporté),
// recherche par nom ou pseudo, « Suggéré » avec des cases à cocher, bouton « Créer ». Le groupe créé s'ouvre.
struct CreateGroupView: View {
    @State private var model: FriendPickerModel
    let onCreated: (Conversation) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: FriendPickerModel, onCreated: @escaping (Conversation) -> Void) {
        _model = State(initialValue: model)
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            FriendPickerList(model: model) {
                GroupTypeRow()
            }
            .navigationTitle("Créer un chat de groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("createGroup.close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                FriendPickerSubmitBar(model: model) {
                    Task {
                        guard let conversation = await model.create() else { return }
                        dismiss()
                        onCreated(conversation)
                    }
                }
            }
        }
    }
}

// Type du groupe : privé seulement (ADR-059).
private struct GroupTypeRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(Color.brandPink)
                .frame(width: 44, height: 44)
                .background(Color.brandPink.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Privé").font(.body.weight(.semibold))
                Text("Pour les amis : seuls les membres ajoutés voient le groupe.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.brandPink)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandPink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("createGroup.type")
    }
}

// Ajouter des membres à un groupe : mêmes amis à cocher, sans ses membres actuels.
struct AddGroupMembersView: View {
    @State private var model: FriendPickerModel
    let add: ([UserSummary]) async -> Bool
    @Environment(\.dismiss) private var dismiss

    init(model: FriendPickerModel, add: @escaping ([UserSummary]) async -> Bool) {
        _model = State(initialValue: model)
        self.add = add
    }

    var body: some View {
        NavigationStack {
            FriendPickerList(model: model) { EmptyView() }
                .navigationTitle("Ajouter des membres")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    FriendPickerSubmitBar(model: model) {
                        Task {
                            if await add(model.selected) { dismiss() }
                        }
                    }
                }
        }
    }
}

// Recherche, comptes choisis et liste « Suggéré » à cocher.
private struct FriendPickerList<Header: View>: View {
    @Bindable var model: FriendPickerModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        List {
            Section {
                header()
                    .listRowSeparator(.hidden)
                if !model.selected.isEmpty {
                    SelectedFriends(model: model)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(model.displayed, id: \.id) { user in
                    Button {
                        model.toggle(user)
                    } label: {
                        FriendRow(
                            user: user, isSelected: model.isSelected(user),
                            isDisabled: !model.isSelected(user) && model.selected.count >= model.maxSelection)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await model.loadMore(ifNeededAfter: user) } }
                    .accessibilityIdentifier("friendPicker.friend")
                }
                listState
            } header: {
                Text(model.results == nil ? "Suggéré" : "Résultats")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher par nom ou pseudo")
        .task { await model.loadFirstIfNeeded() }
        .alert(
            "Chat de groupe",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var listState: some View {
        if model.isSearching || (model.results == nil && model.state == .loading) {
            ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
        } else if case .failed(let message) = model.state, model.results == nil {
            ContentUnavailableView {
                Label("Chargement impossible", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await model.loadMore() } }
            }
            .listRowSeparator(.hidden)
        } else if model.displayed.isEmpty {
            ContentUnavailableView(
                model.results == nil ? "Aucun ami à ajouter" : "Aucun ami trouvé",
                systemImage: "person.2",
                description: Text("Seuls tes amis (les comptes que tu suis et qui te suivent) peuvent rejoindre un groupe.")
            )
            .listRowSeparator(.hidden)
        }
    }
}

// Comptes choisis, en tête : photo et prénom, toucher pour retirer.
private struct SelectedFriends: View {
    let model: FriendPickerModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(model.selected, id: \.id) { user in
                    Button {
                        model.toggle(user)
                    } label: {
                        VStack(spacing: 4) {
                            AvatarView(url: user.avatarURL, name: user.displayName, size: 48)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, Color(.systemGray))
                                }
                            Text(user.displayName).font(.caption).lineLimit(1)
                        }
                        .frame(width: 60)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retirer \(user.displayName)")
                }
            }
        }
    }
}

// Un ami : photo, nom, @pseudo, case à cocher ronde (rose une fois cochée).
private struct FriendRow: View {
    let user: UserSummary
    let isSelected: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarURL, name: user.displayName, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.brandPink) : AnyShapeStyle(Color(.systemGray3)))
        }
        .opacity(isDisabled ? 0.4 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// Grand bouton rose en bas : « Créer (3) », « Ajouter (2) », avec ce qui manque encore.
private struct FriendPickerSubmitBar: View {
    let model: FriendPickerModel
    let submit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let hint = model.hint {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
            Button(action: submit) {
                Group {
                    if model.isSubmitting {
                        DotsLoader()
                    } else {
                        Text(model.submitTitle).font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandPink)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("friendPicker.submit")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
