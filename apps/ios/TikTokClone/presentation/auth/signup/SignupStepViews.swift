import SwiftUI

// Étapes 1 à 4 de l'inscription (ADR-055) : date de naissance, email, mot de passe, pseudo. `next` pousse l'étape
// suivante dans la pile de `AuthFlowView`.

struct SignupBirthdayView: View {
    @Bindable var model: SignupFlowModel
    let next: (SignupStep) -> Void

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .top, spacing: 12) {
                SignupHeader(title: "Quelle est ta date de naissance ?", subtitle: "Elle ne sera pas affichée publiquement.")
                Image(systemName: "birthday.cake.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brandPink, Color.brandCyan)
                    .symbolRenderingMode(.palette)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                UnderlinedField(text: nil) {
                    Text(model.hasPickedBirthDate ? model.birthDate.formatted(date: .long, time: .omitted) : "Date de naissance")
                        .foregroundStyle(model.hasPickedBirthDate ? .primary : .tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("signup.birthday.value")
                }
                if let problem = model.birthDateProblem {
                    SignupErrorText(message: problem, identifier: "signup.birthday.error")
                }
            }
            SignupPrimaryButton(title: "Suivant", isEnabled: model.canContinueFromBirthday) { next(.email) }
                .accessibilityIdentifier("signup.birthday.next")
            Spacer()
            DatePicker("Date de naissance", selection: $model.birthDate, in: model.birthDateRange, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .accessibilityIdentifier("signup.birthday.picker")
        }
        .signupPage()
        .onAppear { model.viewed(.birthday) }
    }
}

struct SignupEmailView: View {
    @Bindable var model: SignupFlowModel
    let next: (SignupStep) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            SignupHeader(title: "Quelle est ton adresse email ?")
            VStack(alignment: .leading, spacing: 12) {
                UnderlinedField(text: $model.email) {
                    TextField("Adresse email", text: $model.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.continue)
                        .onSubmit(continueIfPossible)
                        .accessibilityIdentifier("signup.email.field")
                }
                if let error = model.emailError {
                    SignupErrorText(message: error, identifier: "signup.email.error")
                }
                Text("Elle sert à te connecter et n’est jamais affichée publiquement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            SignupPrimaryButton(title: "Continuer", isEnabled: model.canContinueFromEmail, action: continueIfPossible)
                .accessibilityIdentifier("signup.email.next")
        }
        .signupPage()
        // Suggestions de domaines au-dessus du clavier, comme TikTok.
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RegistrationRules.emailDomains, id: \.self) { domain in
                            Button("@\(domain)") { model.completeEmail(with: domain) }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("signup.email.domain.\(domain)")
                        }
                    }
                }
            }
        }
        .onAppear {
            focused = true
            model.viewed(.email)
        }
    }

    private func continueIfPossible() {
        guard model.canContinueFromEmail else { return }
        next(.password)
    }
}

struct SignupPasswordView: View {
    @Bindable var model: SignupFlowModel
    let next: (SignupStep) -> Void
    @State private var isRevealed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupHeader(title: "Crée un mot de passe")
            UnderlinedField(text: $model.password) {
                Group {
                    if isRevealed {
                        TextField("Mot de passe", text: $model.password)
                    } else {
                        SecureField("Mot de passe", text: $model.password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.next)
                .onSubmit(continueIfPossible)
                .accessibilityIdentifier("signup.password.field")
            } trailing: {
                Button(isRevealed ? "Masquer" : "Afficher", systemImage: isRevealed ? "eye" : "eye.slash") {
                    isRevealed.toggle()
                    focused = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Ton mot de passe doit contenir :").font(.subheadline.weight(.semibold))
                PasswordRule(text: "8 caractères au minimum", isMet: model.passwordChecks.length)
                PasswordRule(text: "Au moins une lettre et un chiffre", isMet: model.passwordChecks.letterAndDigit)
                PasswordRule(text: "Un caractère spécial, conseillé (# ? ! $ & @)", isMet: model.passwordChecks.specialCharacter)
            }
            PasswordStrengthGauge(strength: model.passwordStrength)
            SignupPrimaryButton(title: "Suivant", isEnabled: model.canContinueFromPassword, action: continueIfPossible)
                .accessibilityIdentifier("signup.password.next")
        }
        .signupPage()
        .onAppear {
            focused = true
            model.viewed(.password)
        }
    }

    private func continueIfPossible() {
        guard model.canContinueFromPassword else { return }
        next(.username)
    }
}

private struct PasswordRule: View {
    let text: String
    let isMet: Bool

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(isMet ? Color.green : Color(.tertiaryLabel))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMet ? "respecté" : "non respecté")
    }
}

// Jauge de solidité, indicative (ADR-055) : faible, moyen, fort.
private struct PasswordStrengthGauge: View {
    let strength: RegistrationRules.PasswordStrength

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.secondarySystemFill))
                    Capsule().fill(color).frame(width: max(proxy.size.width * fraction, strength == .none ? 4 : 0))
                }
            }
            .frame(height: 5)
            .animation(.snappy, value: strength)
            HStack(spacing: 4) {
                Text("Solidité du mot de passe :")
                Text(label).fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("signup.password.strength")
    }

    private var fraction: CGFloat {
        switch strength {
        case .none: 0
        case .weak: 1 / 3
        case .medium: 2 / 3
        case .strong: 1
        }
    }

    private var color: Color {
        switch strength {
        case .none: Color(.tertiaryLabel)
        case .weak: .yellow
        case .medium: .orange
        case .strong: .green
        }
    }

    private var label: String {
        switch strength {
        case .none: ""
        case .weak: "Faible"
        case .medium: "Moyen"
        case .strong: "Fort"
        }
    }
}

struct SignupUsernameView: View {
    @Bindable var model: SignupFlowModel
    let next: (SignupStep) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SignupHeader(
                title: "Crée ton pseudo",
                subtitle: "Il permet de te retrouver et de te connecter. Ton nom affiché sera le même ; tu pourras changer les deux plus tard.")
            VStack(alignment: .leading, spacing: 10) {
                UnderlinedField(text: $model.username) {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("pseudo", text: $model.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(submit)
                            .accessibilityIdentifier("signup.username.field")
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    status
                    Spacer()
                    Text("\(model.username.count)/\(RegistrationRules.maxUsernameLength)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(model.username.count > RegistrationRules.maxUsernameLength ? .red : .secondary)
                }
                if let error = model.usernameError {
                    SignupErrorText(message: error, identifier: "signup.username.error")
                }
            }
            SignupPrimaryButton(title: "Confirmer", isEnabled: model.canSubmit, isLoading: model.isSubmitting, action: submit)
                .accessibilityIdentifier("signup.username.submit")
        }
        .signupPage()
        .onChange(of: model.username) { model.normalizeUsername() }
        // Une vérification par saisie : la frappe suivante annule la précédente (délai sans frappe dans le modèle).
        .task(id: model.username) { await model.usernameChanged() }
        .onAppear {
            focused = true
            model.viewed(.username)
        }
    }

    @ViewBuilder private var status: some View {
        Group {
            switch model.usernameStatus {
            case .idle: Text(" ")
            case .checking: Text("Vérification…").foregroundStyle(.secondary)
            case .checked(.available): Label("Disponible", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .checked(.taken): Text("Ce pseudo est déjà pris.").foregroundStyle(.red)
            case .checked(.reserved): Text("Ce pseudo n’est pas disponible.").foregroundStyle(.red)
            case .checked(.invalid):
                Text("2 à 24 caractères : lettres minuscules, chiffres, « . » et « _ ».").foregroundStyle(.red)
            case .unknown: Text("Disponibilité vérifiée à la création du compte.").foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("signup.username.status")
    }

    private func submit() {
        Task {
            if let step = await model.submit() { next(step) }
        }
    }
}
