import SwiftUI

// « Description pour l'accessibilité » (ADR-076) : texte alternatif de la vidéo, lu par VoiceOver aux personnes aveugles ou
// malvoyantes. 300 caractères au plus (compteur), facultatif ; nettoyé à la publication comme par l'API.
struct AltTextEditorView: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var remaining: Int { AltTextRules.maxLength - (AltTextRules.cleaned(text)?.count ?? 0) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(AltTextSpeech.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Décris ce qu'on voit dans la vidéo…", text: $text, axis: .vertical)
                    .font(.body)
                    .lineLimit(4...10)
                    .focused($isFocused)
                    .padding(12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Description pour l'accessibilité")
                    .accessibilityHint(AltTextSpeech.explanation)
                    .accessibilityIdentifier("publish.altText.field")
                HStack {
                    if !text.isEmpty {
                        Button("Effacer") { text = "" }
                            .font(.subheadline)
                            .accessibilityLabel("Effacer le texte alternatif")
                            .accessibilityIdentifier("publish.altText.clear")
                    }
                    Spacer()
                    Text(remaining, format: .number)
                        .font(.caption)
                        .foregroundStyle(remaining < 0 ? .red : .secondary)
                        .accessibilityLabel(AltTextSpeech.remaining(remaining))
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("Description pour l'accessibilité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .disabled(remaining < 0)
                        .accessibilityIdentifier("publish.altText.done")
                }
            }
        }
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }
}
