import SwiftUI

struct RegisterView: View {
    @State private var viewModel: RegisterViewModel

    init(viewModel: RegisterViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $viewModel.displayName)
                    .textContentType(.name)
                    .accessibilityIdentifier("register.displayName")
                TextField("Pseudo", text: $viewModel.username)
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.username) { viewModel.normalizeUsername() }
                    .accessibilityIdentifier("register.username")
            } header: {
                Text("Profil")
            } footer: {
                Text("2 à 24 caractères : lettres minuscules, chiffres, « . » et « _ ».")
            }

            Section {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("register.email")
                SecureField("Mot de passe", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("register.password")
            } header: {
                Text("Connexion")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("register.error")
                } else {
                    Text("8 caractères au minimum.")
                }
            }

            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting { ProgressView() } else { Text("Créer mon compte").bold() }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("register.submit")
            }
        }
        .navigationTitle("Inscription")
    }
}
