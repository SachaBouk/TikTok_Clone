import SwiftUI

// Textes et autocollants posés sur la vidéo, comme TikTok (ADR-052, ADR-062, ADR-063) : éditeur de texte plein écran
// (police, couleur, fond, alignement), puis texte ou autocollant déplacé au doigt sur l'aperçu (repère central, corbeille
// « Supprimer »), pincé pour changer sa taille.

// Texte en cours de saisie : nouveau (`overlay` nil) ou existant.
struct TextDraft: Identifiable {
    let id = UUID()
    let overlay: TextOverlay?
}

extension EditorTextStyle {
    var swiftUIFont: Font { Font(font as CTFont) }

    var textColor: Color { Color(uiColor: textUIColor) }

    var multilineAlignment: TextAlignment {
        switch style.alignment {
        case .center: .center
        case .left: .leading
        case .right: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch style.alignment {
        case .center: .center
        case .left: .leading
        case .right: .trailing
        }
    }

    // Fond du texte (couleur et opacité) ; transparent sans fond.
    var fillColor: Color {
        guard let fill = style.fill else { return .clear }
        let rgb = fill.color.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue).opacity(fill.opacity)
    }

    var shadowColor: Color {
        guard style.background == .none else { return .clear }
        return style.textColor == .black ? .white.opacity(0.6) : .black.opacity(0.6)
    }
}

// Texte mis en page comme à l'export : mêmes lignes (largeur mesurée par UIKit), marges et fond arrondi.
struct StyledTextBox: View {
    let text: String
    let layout: EditorTextStyle

    var body: some View {
        Text(text)
            .font(layout.swiftUIFont)
            .foregroundStyle(layout.textColor)
            .multilineTextAlignment(layout.multilineAlignment)
            .frame(width: layout.textSize(for: text).width + 1, alignment: layout.frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: layout.shadowColor, radius: layout.shadowRadius)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .background(layout.fillColor, in: RoundedRectangle(cornerRadius: layout.cornerRadius))
    }
}

// Texte ou autocollant de l'aperçu : glisser le déplace (repère central et corbeille affichés par `EditorCanvas`), pincer
// change sa taille, toucher le rouvre (texte). Positions relatives à l'image ; `content` reçoit l'échelle en cours.
struct DraggableOverlay<Content: View>: View {
    let center: CGPoint
    let scale: Double
    let size: CGSize
    let label: String
    let hint: String
    let identifier: String
    @ViewBuilder let content: (Double) -> Content
    // Centre (aimanté) et position du doigt pendant le glissement.
    let onDragChanged: (CGPoint, CGPoint) -> Void
    let onDragEnded: (CGPoint, CGPoint) -> Void
    let onScale: (Double) -> Void
    var onTap: (() -> Void)?
    @State private var dragOffset: CGSize = .zero
    @State private var magnification: CGFloat = 1
    @State private var isOverTrash = false

    var body: some View {
        let current = currentCenter
        content(scale * magnification)
            .scaleEffect(isOverTrash ? 0.6 : 1)
            .opacity(isOverTrash ? 0.5 : 1)
            .animation(.snappy(duration: 0.15), value: isOverTrash)
            .position(x: current.x * size.width, y: current.y * size.height)
            .gesture(
                DragGesture(coordinateSpace: .named(EditorCanvas.coordinateSpace))
                    .onChanged { value in
                        dragOffset = value.translation
                        let finger = relative(value.location)
                        isOverTrash = TextDragRules.isOverTrash(finger)
                        onDragChanged(currentCenter, finger)
                    }
                    .onEnded { value in
                        let center = currentCenter
                        let finger = relative(value.location)
                        // Lâché sur la corbeille : il reste dessous pendant qu'il disparaît.
                        if !TextDragRules.isOverTrash(finger) {
                            dragOffset = .zero
                            isOverTrash = false
                        }
                        onDragEnded(center, finger)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { magnification = $0.magnification }
                    .onEnded { value in
                        magnification = 1
                        onScale(scale * value.magnification)
                    }
            )
            .onTapGesture { onTap?() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
    }

    // Centre pendant le glissement, aimanté au repère vertical.
    private var currentCenter: CGPoint {
        let moved = CGPoint(x: center.x + dragOffset.width / max(size.width, 1), y: center.y + dragOffset.height / max(size.height, 1))
        return dragOffset == .zero ? center : TextDragRules.snapped(moved).center
    }

    private func relative(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
    }
}

// Autocollant mis en page comme à l'export (`StickerStyle`).
struct StickerView: View {
    let sticker: StickerOverlay
    let scale: Double
    let width: CGFloat

    var body: some View {
        let style = StickerStyle(kind: sticker.kind, scale: scale, width: width)
        Text(sticker.text)
            .font(Font(style.font as CTFont))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .shadow(color: sticker.kind == .emoji ? .clear : .black.opacity(0.5), radius: style.shadowRadius)
    }
}

// Repère vertical cyan et corbeille « Supprimer », affichés pendant le déplacement d'un texte.
struct TextDragGuides: View {
    let onGuide: Bool
    let overTrash: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if onGuide {
                Rectangle()
                    .fill(Color.brandCyan)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: overTrash ? 30 : 24, weight: .medium))
                    .foregroundStyle(overTrash ? Color.red : .white)
                    .frame(width: 52, height: 52)
                    .background(overTrash ? Color.white : .black.opacity(0.25), in: Circle())
                Text("Supprimer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .shadow(radius: 3)
            .padding(.top, 12)
            .animation(.snappy(duration: 0.15), value: overTrash)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .sensoryFeedback(.impact(weight: .light), trigger: onGuide) { _, new in new }
        .sensoryFeedback(.impact, trigger: overTrash) { _, new in new }
    }
}

// Éditeur de texte plein écran, comme TikTok : vidéo assombrie, « Terminé » en haut à droite, texte au centre écrit en
// direct dans son style ; au-dessus du clavier, fond (« A »), alignement, polices, puis la palette de couleurs.
// « Terminé » valide ; un texte vide n'est pas ajouté (ou est retiré).
struct TextEditorOverlay: View {
    let draft: TextDraft
    let onDone: (String, TextOverlay.Style) -> Void
    @State private var text: String
    @State private var style: TextOverlay.Style
    @FocusState private var focused: Bool

    init(draft: TextDraft, onDone: @escaping (String, TextOverlay.Style) -> Void) {
        self.draft = draft
        self.onDone = onDone
        _text = State(initialValue: draft.overlay?.text ?? "")
        _style = State(initialValue: draft.overlay?.style ?? TextOverlay.Style())
    }

    var body: some View {
        ZStack {
            // Le fond ne valide pas : un toucher qui ferme une alerte du système (collage) y retombe.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            GeometryReader { geometry in
                let layout = EditorTextStyle(style: style, scale: draft.overlay?.scale ?? 1, width: geometry.size.width)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Terminé", action: finish)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .accessibilityIdentifier("textEditor.done")
                    }
                    Spacer(minLength: 0)
                    field(layout)
                    Spacer(minLength: 0)
                    toolbar
                    colors
                        .padding(.vertical, 12)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        // Focus posé un instant après l'apparition : posé dans `onAppear`, il est parfois perdu (clavier absent).
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
        }
        .onChange(of: text) { _, value in
            if value.count > EditPlan.maxTextLength { text = String(value.prefix(EditPlan.maxTextLength)) }
        }
    }

    // Champ de saisie mis en page comme le texte posé : il grandit avec le texte, dans son fond.
    private func field(_ layout: EditorTextStyle) -> some View {
        TextField("", text: $text, axis: .vertical)
            .font(layout.swiftUIFont)
            .foregroundStyle(layout.textColor)
            .multilineTextAlignment(layout.multilineAlignment)
            .tint(Color.brandPink)
            .focused($focused)
            .frame(width: layout.textSize(for: text).width + 8)
            .shadow(color: layout.shadowColor, radius: layout.shadowRadius)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .background(layout.fillColor, in: RoundedRectangle(cornerRadius: layout.cornerRadius))
            .accessibilityLabel("Ton texte")
            .accessibilityIdentifier("textEditor.field")
    }

    // Fond, alignement, puis les polices (défilantes).
    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                style.background = style.background.next
            } label: {
                TextBackgroundIcon(background: style.background)
            }
            .accessibilityLabel("Fond du texte")
            .accessibilityValue(style.background.title)
            .accessibilityIdentifier("textEditor.background")
            Button {
                style.alignment = style.alignment.next
            } label: {
                Image(systemName: alignmentSymbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Alignement")
            .accessibilityValue(style.alignment.title)
            .accessibilityIdentifier("textEditor.alignment")
            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 28)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(TextOverlay.Font.allCases) { font in
                        let selected = style.font == font
                        Button {
                            style.font = font
                        } label: {
                            Text(font.title)
                                .font(Font(EditorTextStyle.font(font, size: 17) as CTFont))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8).stroke(
                                        selected ? Color.white : .white.opacity(0.35), lineWidth: selected ? 2 : 1))
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("textEditor.font.\(font.rawValue)")
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.leading, 16)
    }

    private var colors: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(TextOverlay.Color.allCases) { color in
                    let selected = style.color == color
                    let rgb = color.rgb
                    Button {
                        style.color = color
                    } label: {
                        Circle()
                            .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                            .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 2))
                            .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("textEditor.color.\(color.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .animation(.snappy(duration: 0.15), value: style.color)
    }

    private var alignmentSymbol: String {
        switch style.alignment {
        case .center: "text.aligncenter"
        case .left: "text.alignleft"
        case .right: "text.alignright"
        }
    }

    private func finish() {
        focused = false
        onDone(text, style)
    }
}

// Bouton « A » du fond : lettre seule, lettre noire sur carré blanc (fond plein), lettre sur carré translucide.
struct TextBackgroundIcon: View {
    let background: TextOverlay.Background

    var body: some View {
        Text("A")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(background == .solid ? Color.black : .white)
            .frame(width: 32, height: 32)
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: background == .none ? .black.opacity(0.6) : .clear, radius: 2)
            .frame(width: 36, height: 36)
    }

    private var fill: Color {
        switch background {
        case .none: .clear
        case .solid: .white
        case .translucent: .white.opacity(0.35)
        }
    }
}
