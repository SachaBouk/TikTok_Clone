import SwiftUI

// « Modifier le profil », comme TikTok (ADR-056, refait d'après des captures, ADR-070), poussé depuis son profil (crayon
// en haut à gauche) : fond gris, la photo (appareil photo par-dessus) et « Modifier la photo » ; une carte blanche Nom,
// Nom d'utilisateur et lien du profil (à copier) ; « Informations de base » : Bio, Pronom. Chaque ligne ouvre sa page de
// modification, enregistrée à part (« Enregistré »). Hors périmètre : avatars, collecte de fonds.
struct EditProfileView: View {
    let viewModel: EditProfileViewModel
    @State private var isChoosingPhoto = false
    @State private var editingField: ProfileField?
    @State private var copied = false

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photo
                card {
                    row(.name, value: viewModel.profile?.displayName)
                    row(.username, value: viewModel.profile?.username)
                    if let username = viewModel.profile?.username { linkRow(username) }
                }
                sectionTitle("Informations de base")
                card {
                    row(.bio, value: viewModel.profile?.bio)
                    row(.pronouns, value: viewModel.profile?.pronouns)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
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

    // Photo assombrie, appareil photo blanc au centre, puis « Modifier la photo » en bleu-vert.
    private var photo: some View {
        Button {
            isChoosingPhoto = true
        } label: {
            VStack(spacing: 14) {
                AvatarView(url: viewModel.profile?.avatarURL, name: viewModel.profile?.displayName ?? "", size: 112)
                    .overlay {
                        Circle().fill(.black.opacity(0.3))
                        if viewModel.isChangingPhoto {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "camera.fill").font(.system(size: 30)).foregroundStyle(.white)
                        }
                    }
                Text(viewModel.profile?.avatarURL == nil ? "Ajouter une photo" : "Modifier la photo")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Self.photoLinkColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isChangingPhoto)
        .accessibilityIdentifier("editProfile.photo")
    }

    // Bleu-vert du lien « Modifier la photo » (relevé sur une capture).
    static let photoLinkColor = Color(red: 0.0, green: 0.55, blue: 0.6)

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    // Une ligne : le champ à gauche, sa valeur (ou « Ajouter … » en gris) dans une seconde colonne, un chevron.
    private func row(_ field: ProfileField, value: String?) -> some View {
        Button {
            viewModel.reset()
            editingField = field
        } label: {
            let filled = value.flatMap { $0.isEmpty ? nil : $0 }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(field.title)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, alignment: .leading)
                Text(filled ?? field.emptyValue)
                    .font(filled == nil ? .body : .body.weight(.medium))
                    .foregroundStyle(filled == nil ? Color.secondary.opacity(0.7) : Color.primary)
                    .lineLimit(field == .bio ? 4 : 1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").accessibilityHidden(true).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editProfile.\(field.rawValue)")
    }

    // Lien du profil (comme « tiktok.com/@… »), sous le nom d'utilisateur, avec l'icône de copie.
    private func linkRow(_ username: String) -> some View {
        Button {
            UIPasteboard.general.url = ProfileLink.url(for: username)
            copied = true
            viewModel.notice = "Lien copié"
        } label: {
            HStack(spacing: 12) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                Text(ProfileLink.url(for: username).absoluteString)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: copied ? "checkmark" : "square.on.square").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copier le lien du profil")
        .accessibilityIdentifier("editProfile.copyLink")
    }

    private static let labelWidth: CGFloat = 110
}

// Champ du profil modifiable sur sa propre page.
enum ProfileField: String, Identifiable, Hashable {
    case name, username, bio, pronouns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Nom"
        case .username: "Nom d'utilisateur"
        case .bio: "Bio"
        case .pronouns: "Pronom"
        }
    }

    var emptyValue: String {
        switch self {
        case .name: "Ajouter un nom"
        case .username: "Ajouter un pseudo"
        case .bio: "Rédige une courte description qui raconte qui tu es ou de quoi parle ton compte."
        case .pronouns: "Ajouter des pronoms"
        }
    }

    var placeholder: String {
        switch self {
        case .name: "Ton nom"
        case .username: "Ton pseudo"
        case .bio: "Ajoute une bio"
        case .pronouns: "elle, il, iel…"
        }
    }

    var maxLength: Int {
        switch self {
        case .name: RegistrationRules.displayNameLength.upperBound
        case .username: 24
        case .bio: ProfileRules.maxBioLength
        case .pronouns: ProfileRules.maxPronounsLength
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
        case .pronouns: $viewModel.pronouns
        }
    }

    private var hasChanged: Bool {
        let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name: return value != viewModel.profile?.displayName
        case .username: return value != viewModel.profile?.username
        case .bio: return value != (viewModel.profile?.bio ?? "")
        case .pronouns: return value != (viewModel.profile?.pronouns ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(field.placeholder, text: text, axis: field == .bio ? .vertical : .horizontal)
                .lineLimit(field == .bio ? 4...8 : 1...1)
                .textInputAutocapitalization(field == .username || field == .pronouns ? .never : .sentences)
                .autocorrectionDisabled(field == .username || field == .pronouns)
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
            if field == .pronouns {
                Text("Affichés à côté de ton nom d'utilisateur, sur ton profil. Laisse vide pour les retirer.")
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
