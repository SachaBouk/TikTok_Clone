import PhotosUI
import SwiftUI

// Feuille « Modifier le profil » (formulaire natif). La photo s'applique tout de suite ; nom, pseudo et bio
// avec « Enregistrer ».
struct EditProfileView: View {
    @State private var viewModel: EditProfileViewModel
    @State private var photoItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: EditProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        AvatarView(url: viewModel.profile?.avatarURL, name: viewModel.displayName, size: 96)
                            .overlay {
                                if viewModel.isChangingPhoto {
                                    Circle().fill(.black.opacity(0.4))
                                    ProgressView().tint(.white)
                                }
                            }
                        HStack(spacing: 20) {
                            PhotosPicker(viewModel.profile?.avatarURL == nil ? "Ajouter une photo" : "Changer la photo",
                                         selection: $photoItem, matching: .images)
                                .accessibilityIdentifier("editProfile.photo")
                            if viewModel.profile?.avatarURL != nil {
                                Button("Supprimer", role: .destructive) { Task { await viewModel.removePhoto() } }
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isChangingPhoto)
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Nom") {
                    TextField("Nom", text: $viewModel.displayName)
                        .textContentType(.name)
                        .accessibilityIdentifier("editProfile.displayName")
                }

                Section {
                    TextField("Pseudo", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .accessibilityIdentifier("editProfile.username")
                } header: {
                    Text("Pseudo")
                } footer: {
                    Text("2 à 24 caractères : lettres minuscules, chiffres, « . » et « _ ». L’ancien pseudo est aussitôt libéré.")
                }

                Section {
                    TextField("Présente-toi", text: $viewModel.bio, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("editProfile.bio")
                } header: {
                    Text("Bio")
                } footer: {
                    Text("\(viewModel.remainingBioCharacters) caractères restants")
                        .foregroundStyle(viewModel.remainingBioCharacters < 0 ? .red : .secondary)
                }
            }
            .navigationTitle("Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") {
                            Task { if await viewModel.save() { dismiss() } }
                        }
                        .disabled(!viewModel.hasChanges)
                        .accessibilityIdentifier("editProfile.save")
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        viewModel.errorMessage = "Impossible d’importer cette image."
                        return
                    }
                    await viewModel.changePhoto(data)
                }
            }
            .alert("Profil", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(viewModel.hasChanges)
    }
}
