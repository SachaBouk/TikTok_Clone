import SwiftUI

// Texte alternatif d'une vidéo publiée (ADR-076) : décrit ce qu'on y voit, pour les personnes qui utilisent VoiceOver.
// Vide = retiré. `save` renvoie un message d'erreur, ou nil une fois enregistré.
struct AltTextEditor: View {
    let initialText: String
    let save: (String?) async -> String?
    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var count: Int { (AltTextRules.cleaned(text) ?? "").count }
    private var isTooLong: Bool { count > AltTextRules.maxLength }
    private var hasChanged: Bool { AltTextRules.cleaned(text) != AltTextRules.cleaned(initialText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex. : Un chat roux saute sur un canapé bleu.", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($isFocused)
                        .accessibilityLabel("Texte alternatif")
                        .accessibilityIdentifier("altText.field")
                } header: {
                    Text("Ce qu'on voit dans la vidéo")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lu par VoiceOver aux personnes aveugles ou malvoyantes. Décris les personnes, les actions et le texte affiché.")
                        Text("\(count)/\(AltTextRules.maxLength)")
                            .foregroundStyle(isTooLong ? .red : .secondary)
                            .accessibilityLabel("\(count) caractères sur \(AltTextRules.maxLength)")
                    }
                }
            }
            .navigationTitle("Texte alternatif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            isSaving = true
                            errorMessage = await save(text)
                            isSaving = false
                            if errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(!hasChanged || isTooLong || isSaving)
                    .accessibilityIdentifier("altText.save")
                }
            }
            .alert("Enregistrement impossible", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                text = initialText
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}
