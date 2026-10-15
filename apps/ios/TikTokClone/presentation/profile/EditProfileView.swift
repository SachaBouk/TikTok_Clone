import SwiftUI

// « Modifier le profil », comme TikTok (ADR-056), poussé depuis son profil : la photo (« Changer la photo » : recadrage
// rond, story), puis « À propos de toi » : nom, pseudo (et le lien du profil, à copier), bio. Chaque ligne ouvre sa
// page de modification, enregistrée à part (« Enregistré »).
struct EditProfileView: View {
    let viewModel: EditProfileViewModel
    @State private var isChoosingPhoto = false
    @State private var editingField: ProfileField?
    @State private var copied = false

    var body: some View {
        @Bindable var viewModel = viewModel
        List {
            Section {
                Button {
                    isChoosingPhoto = true
                } label: {
                    VStack(spacing: 12) {
                        AvatarView(url: viewModel.profile?.avatarURL, name: viewModel.profile?.displayName ?? "", size: 96)
                            .overlay {
                                Circle().fill(.black.opacity(0.3))
                                if viewModel.isChangingPhoto {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "camera").font(.title).foregroundStyle(.white)
                                }
                            }
                        Text(viewModel.profile?.avatarURL == nil ? "Ajouter une photo" : "Changer la photo")
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isChangingPhoto)
                .accessibilityIdentifier("editProfile.photo")
            }
            .listRowSeparator(.hidden)

            Section {
                row(.name, value: viewModel.profile?.displayName)
                row(.username, value: viewModel.profile?.username)
                if let username = viewModel.profile?.username {
                    // Lien du profil, à copier (comme « tiktok.com/@… »).
                    Button {
                        UIPasteboard.general.url = ProfileLink.url(for: username)
                        copied = true
                        viewModel.notice = "Lien copié"
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            Text(ProfileLink.url(for: username).absoluteString).lineLimit(1).truncationMode(.middle)
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copier le lien du profil")
                    .accessibilityIdentifier("editProfile.copyLink")
                }
                row(.bio, value: viewModel.profile?.bio)
            } header: {
                Text("À propos de toi")
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Modifier le profil")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editingField) { field in
            ProfileFieldEditor(field: field, viewModel: viewModel)
        }
        .avatarPhotoFlow(isPresented: $isChoosingPhoto, viewModel: viewModel)
        .toast($viewModel.notice)
        .alert(
            "Profil",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil && editingField == nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // Une ligne : le champ, sa valeur (ou « Ajouter … » en gris), un chevron.
    private func row(_ field: ProfileField, value: String?) -> some View {
        Button {
            viewModel.reset()
            editingField = field
        } label: {
            HStack(spacing: 12) {
                Text(field.title).foregroundStyle(.primary)
                Spacer(minLength: 16)
                Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? field.emptyValue)
                    .foregroundStyle(value?.isEmpty == false ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editProfile.\(field.rawValue)")
    }
}

// Champ du profil modifiable sur sa propre page.
enum ProfileField: String, Identifiable, Hashable {
    case name, username, bio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Nom"
        case .username: "Pseudo"
        case .bio: "Bio"
        }
    }

    var emptyValue: String {
        switch self {
        case .name: "Ajouter un nom"
        case .username: "Ajouter un pseudo"
        case .bio: "Ajouter une bio"
        }
    }

    var placeholder: String {
        switch self {
        case .name: "Ton nom"
        case .username: "Ton pseudo"
        case .bio: "Ajoute une bio"
        }
    }

    var maxLength: Int {
        switch self {
        case .name: RegistrationRules.displayNameLength.upperBound
        case .username: 24
        case .bio: ProfileRules.maxBioLength
        }
    }
}

// Page d'un champ, comme TikTok : « Annuler », le titre, « Enregistrer » (rose quand le champ a changé), le champ et
// son compteur. Enregistré seul (`EditProfileViewModel.save` n'envoie que les champs changés), puis retour.
struct ProfileFieldEditor: View {
    let field: ProfileField
    @Bindable var viewModel: EditProfileViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var text: Binding<String> {
        switch field {
        case .name: $viewModel.displayName
        case .username: $viewModel.username
        case .bio: $viewModel.bio
        }
    }

    private var hasChanged: Bool {
        let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name: return value != viewModel.profile?.displayName
        case .username: return value != viewModel.profile?.username
        case .bio: return value != (viewModel.profile?.bio ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(field.placeholder, text: text, axis: field == .bio ? .vertical : .horizontal)
                .lineLimit(field == .bio ? 4...8 : 1...1)
                .textInputAutocapitalization(field == .username ? .never : .sentences)
                .autocorrectionDisabled(field == .username)
                .focused($isFocused)
                .padding(.vertical, 8)
                .accessibilityIdentifier("editProfile.field")
            Divider()
            Text("\(text.wrappedValue.count)/\(field.maxLength)")
                .font(.footnote)
                .foregroundStyle(text.wrappedValue.count > field.maxLength ? .red : .secondary)
            if field == .username {
                Text("2 à 24 caractères : lettres minuscules, chiffres, « . » et « _ ». L’ancien pseudo est aussitôt libéré.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") {
                    viewModel.reset()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Enregistrer") {
                        Task { if await viewModel.save() { dismiss() } }
                    }
                    .tint(hasChanged ? Color.brandPink : .secondary)
                    .disabled(!hasChanged)
                    .accessibilityIdentifier("editProfile.save")
                }
            }
        }
        .onAppear { isFocused = true }
        .alert(
            field.title,
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
