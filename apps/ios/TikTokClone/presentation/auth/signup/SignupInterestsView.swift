import SwiftUI

// Étape 5 de l'inscription (ADR-055) : centres d'intérêt, compte déjà créé (pas de retour en arrière). Sans effet sur le
// feed pour l'instant : le texte ne promet pas de recommandations.
struct SignupInterestsView: View {
    @Bindable var model: SignupFlowModel
    let next: (SignupStep) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choisis tes centres d’intérêt")
                        .font(.system(size: 34, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Dis-nous ce que tu aimes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                switch model.catalogState {
                case .loading:
                    DotsLoader().frame(maxWidth: .infinity).padding(.top, 40)
                case .failed:
                    ContentUnavailableView {
                        Label("Impossible de charger la liste", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Réessayer") { Task { await model.loadInterests() } }
                    }
                case .loaded:
                    InterestChips(catalog: model.catalog, selected: model.selectedInterests) { model.toggle($0) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadInterests() }
        .onAppear { model.viewed(.interests) }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            if let error = model.interestsError {
                SignupErrorText(message: error, identifier: "signup.interests.error").padding(.horizontal, 24)
            }
            HStack(spacing: 12) {
                SignupSecondaryButton(title: "Passer") {
                    model.skipInterests()
                    next(.tutorial)
                }
                .accessibilityIdentifier("signup.interests.skip")
                SignupPrimaryButton(title: "Suivant", isEnabled: !model.selectedInterests.isEmpty, isLoading: model.isSavingInterests) {
                    Task { if await model.submitInterests() { next(.tutorial) } }
                }
                .accessibilityIdentifier("signup.interests.next")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

// Pastilles à sélection multiple : emoji et nom ; choisie, fond rose et coche à la place de l'emoji.
struct InterestChips: View {
    let catalog: [Interest]
    let selected: Set<String>
    let toggle: (Interest) -> Void

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 12) {
            ForEach(catalog) { interest in
                let isSelected = selected.contains(interest.code)
                Button {
                    toggle(interest)
                } label: {
                    HStack(spacing: 10) {
                        if isSelected {
                            Image(systemName: "checkmark").fontWeight(.bold).frame(width: 26)
                        } else {
                            Text(interest.emoji).font(.title2).frame(width: 26)
                        }
                        Text(interest.name).font(.headline)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 20)
                    .frame(height: 50)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.brandPink : Color(.systemBackground), in: Capsule())
                    .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color(.separator)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.2), value: isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("signup.interest.\(interest.code)")
            }
        }
    }
}
