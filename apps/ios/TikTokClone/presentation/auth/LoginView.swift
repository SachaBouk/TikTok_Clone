import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case identifier, password
    }

    init(viewModel: LoginViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                // Email ou pseudo (ADR-055).
                TextField("Email ou nom d’utilisateur", text: $viewModel.identifier)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .identifier)
                    .submitLabel(.next)
                    .accessibilityIdentifier("login.email")
                SecureField("Mot de passe", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .accessibilityIdentifier("login.password")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("login.error")
                }
            }

            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting { ProgressView() } else { Text("Se connecter").bold() }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("login.submit")
            }

            Section {
                NavigationLink("Créer un compte", value: AuthFlowView.Route.register)
                    .accessibilityIdentifier("login.register")
            } footer: {
                Text("Pas encore de compte ?")
            }
        }
        .navigationTitle("Connexion")
        .onSubmit {
            switch focusedField {
            case .identifier: focusedField = .password
            default: Task { await viewModel.submit() }
            }
        }
        .onAppear { focusedField = .identifier }
    }
}
