import SwiftUI

// Textes posés sur la vidéo (ADR-052) : saisie (contenu, couleur, taille) et déplacement au doigt sur l'aperçu.

// Texte en cours de saisie : nouveau (`overlay` nil) ou existant.
struct TextDraft: Identifiable {
    let id = UUID()
    let overlay: TextOverlay?
}

// Texte de l'aperçu, aux proportions de l'export (`EditorTextStyle`) : glisser le déplace, toucher le modifie.
struct DraggableText: View {
    let overlay: TextOverlay
    let size: CGSize
    let onMove: (CGPoint) -> Void
    let onTap: () -> Void
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        let style = EditorTextStyle(overlay: overlay, width: size.width)
        let rgb = overlay.color.rgb
        Text(overlay.text)
            .font(.system(size: style.fontSize, weight: .heavy))
            .foregroundStyle(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
            .multilineTextAlignment(.center)
            .shadow(color: overlay.color == .black ? .white.opacity(0.6) : .black.opacity(0.6), radius: style.shadowRadius)
            .frame(maxWidth: style.maxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .position(x: overlay.center.x * size.width + dragOffset.width, y: overlay.center.y * size.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        dragOffset = .zero
                        onMove(
                            CGPoint(
                                x: overlay.center.x + value.translation.width / size.width,
                                y: overlay.center.y + value.translation.height / size.height))
                    }
            )
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Touche pour modifier le texte")
    }
}

// Saisie d'un texte : contenu, couleur, taille ; « Supprimer » pour un texte existant.
struct TextOverlaySheet: View {
    enum Result {
        case save(String, TextOverlay.Color, TextOverlay.Size)
        case delete
    }

    let draft: TextDraft
    let onDone: (Result) -> Void
    @State private var text: String
    @State private var color: TextOverlay.Color
    @State private var size: TextOverlay.Size
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(draft: TextDraft, onDone: @escaping (Result) -> Void) {
        self.draft = draft
        self.onDone = onDone
        _text = State(initialValue: draft.overlay?.text ?? "")
        _color = State(initialValue: draft.overlay?.color ?? .white)
        _size = State(initialValue: draft.overlay?.size ?? .medium)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ton texte", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focused)
                        .accessibilityIdentifier("editor.textField")
                } footer: {
                    Text("\(EditPlan.maxTextLength - text.count) caractères restants")
                        .foregroundStyle(text.count > EditPlan.maxTextLength ? .red : .secondary)
                }
                Section("Couleur") {
                    HStack {
                        ForEach(TextOverlay.Color.allCases) { option in
                            let rgb = option.rgb
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                                    .overlay(
                                        Circle().stroke(
                                            option == color ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: option == color ? 3 : 1)
                                    )
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                            if option != TextOverlay.Color.allCases.last { Spacer(minLength: 0) }
                        }
                    }
                }
                Section("Taille") {
                    Picker("Taille", selection: $size) {
                        ForEach(TextOverlay.Size.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if draft.overlay != nil {
                    Section {
                        Button("Supprimer le texte", role: .destructive) {
                            onDone(.delete)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.overlay == nil ? "Nouveau texte" : "Modifier le texte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onDone(.save(text, color, size))
                        dismiss()
                    }
                    .disabled(EditPlan.sanitizedText(text) == nil && draft.overlay == nil)
                    .accessibilityIdentifier("editor.textDone")
                }
            }
            .onAppear { focused = true }
        }
    }
}
