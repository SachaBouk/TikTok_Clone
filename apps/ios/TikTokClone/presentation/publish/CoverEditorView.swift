import AVFoundation
import SwiftUI

// Titre de la couverture dans son style (ADR-065), comme TikTok (sans son logo : la note de l'app). Même vue à l'écran
// et dans l'image envoyée (`CoverRenderer`) ; `unit` est la largeur de référence (largeur de l'image / 10).
struct CoverTitleView: View {
    let style: CoverTitleStyle
    let text: String
    var unit: CGFloat = 36
    // Texte grisé quand il est vide (« Saisis un texte »).
    var placeholder = false

    private var shown: String { text.isEmpty ? "Saisis un texte" : text }
    private var fontSize: CGFloat { unit * 0.9 }

    var body: some View {
        content
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: unit * 8.4)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .standard:
            label(.white, weight: .heavy)
                .shadow(color: .black.opacity(0.55), radius: unit * 0.08, y: unit * 0.04)
        case .vector:
            label(.white, weight: .heavy)
                .padding(.horizontal, unit * 0.4)
                .padding(.vertical, unit * 0.15)
                .background(Color.brandPink)
                .overlay { Rectangle().stroke(.black, lineWidth: unit * 0.06).offset(x: unit * 0.12, y: unit * 0.12) }
        case .glitch:
            ZStack {
                label(Color.brandCyan, weight: .black).offset(x: -unit * 0.07)
                label(Color.brandPink, weight: .black).offset(x: unit * 0.07)
                label(.white, weight: .black)
            }
            .padding(.horizontal, unit * 0.4)
            .padding(.vertical, unit * 0.15)
            .background(.black)
        case .tint:
            label(.black, weight: .heavy)
                .padding(.horizontal, unit * 0.4)
                .padding(.vertical, unit * 0.15)
                .background(.white)
                .background { Rectangle().fill(Color.brandCyan).offset(x: -unit * 0.12, y: -unit * 0.12) }
                .background { Rectangle().fill(Color.brandPink).offset(x: unit * 0.12, y: unit * 0.12) }
        case .retro:
            label(Color(red: 0.98, green: 0.86, blue: 0.1), weight: .black, italic: true)
                .shadow(color: .black, radius: 0, x: unit * 0.08, y: unit * 0.08)
                .rotationEffect(.degrees(-6))
        case .skew:
            label(.black, weight: .heavy)
                .padding(.horizontal, unit * 0.6)
                .padding(.vertical, unit * 0.3)
                .background(.white)
                .overlay(alignment: .topLeading) { noteBadge(.black, size: unit * 1.1).offset(x: -unit * 0.1, y: -unit * 0.9) }
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.12, d: 1, tx: 0, ty: 0))
        case .pill:
            label(.white, weight: .heavy)
                .padding(.horizontal, unit * 0.6)
                .padding(.vertical, unit * 0.25)
                .background(Color(red: 0.6, green: 0.6, blue: 0.98), in: Capsule())
                .overlay(alignment: .topTrailing) { noteBadge(.black, size: unit * 0.8, round: true).offset(x: unit * 0.2, y: -unit * 0.3) }
        case .pop:
            label(Color(red: 0.13, green: 0.29, blue: 0.85), weight: .heavy)
                .padding(.horizontal, unit * 0.4)
                .padding(.vertical, unit * 0.15)
                .background(.white)
                .overlay { Rectangle().stroke(Color(red: 0.13, green: 0.29, blue: 0.85), lineWidth: unit * 0.05) }
                .background {
                    Rectangle().stroke(Color(red: 0.13, green: 0.29, blue: 0.85), lineWidth: unit * 0.05).offset(x: unit * 0.15, y: unit * 0.15)
                }
        case .bubble:
            label(.white, weight: .heavy)
                .padding(.horizontal, unit * 0.5)
                .padding(.vertical, unit * 0.25)
                .background(Color(red: 0.25, green: 0.78, blue: 0.62), in: RoundedRectangle(cornerRadius: unit * 0.35))
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: unit * 0.5))
                        .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.62))
                        .offset(x: unit * 0.5, y: unit * 0.35)
                }
        }
    }

    private func label(_ color: Color, weight: Font.Weight, italic: Bool = false) -> some View {
        Text(shown)
            .font(.system(size: fontSize, weight: weight))
            .italic(italic)
            .foregroundStyle(placeholder ? color.opacity(0.45) : color)
    }

    private func noteBadge(_ color: Color, size: CGFloat, round: Bool = false) -> some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.12))
    }
}

// Image de la couverture (ADR-065) : image de la vidéo à l'instant choisi, recadrée en 9:16 (1080 × 1920), titre dessiné au
// centre. JPEG envoyé avec la vidéo.
@MainActor
enum CoverRenderer {
    static let size = CGSize(width: 1080, height: 1920)

    static func image(video: URL, choice: CoverChoice) async -> UIImage? {
        guard let frame = await frame(of: video, at: choice.time, maximumSize: size) else { return nil }
        return compose(frame: frame, choice: choice)
    }

    // Image finale : la frame en plein cadre (remplissage), puis le titre.
    static func compose(frame: CGImage, choice: CoverChoice) -> UIImage {
        let titleImage = choice.shownTitle.flatMap { title in
            choice.style.flatMap { style -> UIImage? in
                let renderer = ImageRenderer(content: CoverTitleView(style: style, text: title, unit: size.width / 10).padding(size.width / 20))
                renderer.scale = 1
                return renderer.uiImage
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let image = UIImage(cgImage: frame)
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
            if let titleImage {
                titleImage.draw(at: CGPoint(x: (size.width - titleImage.size.width) / 2, y: (size.height - titleImage.size.height) / 2))
            }
        }
    }

    // Image de la vidéo à `time` (exacte), orientée.
    nonisolated static func frame(of video: URL, at time: Duration, maximumSize: CGSize) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let seconds = Double(time.components.seconds) + Double(time.components.attoseconds) / 1e18
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
}

// « Modifier la couverture » (ADR-065), comme TikTok : « Annuler » / « Enregistrer », la couverture en grand (toucher le
// titre le modifie), la frise des images de la vidéo (l'image choisie bordée de rose, glisser pour en choisir une autre),
// puis les styles du titre (⊘ Aucun, Standard, Vecteur…).
struct CoverEditorView: View {
    let video: URL
    let duration: Duration
    let onSave: (CoverChoice, UIImage?) -> Void
    let onCancel: () -> Void
    @State private var choice: CoverChoice
    @State private var frames: [Duration: UIImage] = [:]
    @State private var large: UIImage?
    @State private var isEditingTitle = false
    @State private var typing = ""
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(video: URL, duration: Duration, choice: CoverChoice, onSave: @escaping (CoverChoice, UIImage?) -> Void, onCancel: @escaping () -> Void) {
        self.video = video
        self.duration = duration
        self.onSave = onSave
        self.onCancel = onCancel
        _choice = State(initialValue: choice.clamped(to: duration))
    }

    private var frameTimes: [Duration] { CoverChoice.frameTimes(duration: duration) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Annuler", action: onCancel)
                    .accessibilityIdentifier("cover.cancel")
                Spacer()
                Button("Enregistrer") { save() }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                    .accessibilityIdentifier("cover.save")
            }
            .font(.title3)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(height: 52)
            // Pendant la saisie du titre, « Terminé » prend sa place.
            .opacity(isEditingTitle ? 0 : 1)
            preview
                .padding(.horizontal, 60)
                .padding(.top, 8)
            strip
                .padding(.horizontal, 20)
                .padding(.top, 28)
            styles
                .padding(.top, 28)
            Spacer(minLength: 12)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .overlay {
            if isEditingTitle { titleEditor }
        }
        .task { await loadFrames() }
        .task(id: choice.time) {
            if let image = await CoverRenderer.frame(of: video, at: choice.time, maximumSize: CGSize(width: 720, height: 1280)) {
                large = UIImage(cgImage: image)
            }
        }
    }

    // Couverture en grand : l'image choisie et le titre au centre.
    private var preview: some View {
        Color.black
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let large { Image(uiImage: large).resizable().scaledToFill() }
            }
            .clipped()
            .overlay {
                GeometryReader { proxy in
                    if let style = choice.style, !isEditingTitle {
                        CoverTitleView(style: style, text: choice.title, unit: proxy.size.width / 10, placeholder: choice.title.isEmpty)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .onTapGesture { startEditing() }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("cover.title")
                    }
                }
            }
            .accessibilityIdentifier("cover.preview")
    }

    // Frise : une image par dixième de la vidéo ; l'image choisie, plus grande, bordée de rose. Glisser ou toucher choisit.
    private var strip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cell = width / CGFloat(frameTimes.count)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(frameTimes, id: \.self) { time in
                        Color(.systemGray5)
                            .overlay {
                                if let image = frames[time] { Image(uiImage: image).resizable().scaledToFill() }
                            }
                            .frame(width: cell, height: 64)
                            .clipped()
                    }
                }
                .opacity(0.75)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                let fraction = duration > .zero ? choice.time / duration : 0
                Color(.systemGray5)
                    .overlay {
                        if let large { Image(uiImage: large).resizable().scaledToFill() }
                    }
                    .frame(width: cell + 6, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.brandPink, lineWidth: 3) }
                    .offset(x: min(max(0, CGFloat(fraction) * width - 3), width - cell - 6))
                    .allowsHitTesting(false)
            }
            .frame(height: 76)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    choice.time = CoverChoice.time(atFraction: Double(value.location.x / width), duration: duration)
                })
        }
        .frame(height: 76)
        .accessibilityElement()
        .accessibilityLabel("Image de la couverture")
        .accessibilityValue(TimelineTime.label(choice.time))
        .accessibilityAdjustableAction { direction in
            let step = duration / Double(CoverChoice.frameCount)
            choice.time = direction == .increment ? min(choice.time + step, duration - .milliseconds(100)) : max(.zero, choice.time - step)
        }
        .accessibilityIdentifier("cover.strip")
    }

    // Styles du titre : ⊘ Aucun, puis chaque style avec « Titre » pour exemple.
    private var styles: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                styleButton(nil)
                ForEach(CoverTitleStyle.allCases) { styleButton($0) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func styleButton(_ style: CoverTitleStyle?) -> some View {
        let selected = choice.style == style
        return Button {
            choice.style = style
            if style != nil, choice.title.isEmpty { startEditing() }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
                    .frame(width: 76, height: 76)
                    .overlay {
                        if let style {
                            CoverTitleView(style: style, text: "Titre", unit: 9).padding(6)
                        } else {
                            Image(systemName: "nosign").font(.title)
                        }
                    }
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.brandPink, lineWidth: selected ? 3 : 0) }
                Text(style?.title ?? "Aucun")
                    .font(.subheadline)
                    .foregroundStyle(selected ? Color.brandPink : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("cover.style.\(style?.rawValue ?? "none")")
    }

    // Saisie du titre : couverture assombrie, titre dans son style, champ de saisie dessous, « Terminé ».
    private var titleEditor: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button("Terminé") { finishEditing() }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("cover.titleDone")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
                if let style = choice.style {
                    CoverTitleView(style: style, text: typing, unit: 40, placeholder: typing.isEmpty)
                }
                // Champ de saisie sous le titre stylé : le titre suit la frappe.
                TextField("", text: $typing, prompt: Text("Saisis un texte").foregroundStyle(.white.opacity(0.6)))
                    .focused($titleFocused)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .tint(Color.brandPink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .submitLabel(.done)
                    .onSubmit { finishEditing() }
                    .onChange(of: typing) { _, text in
                        if text.count > CoverChoice.maxTitleLength { typing = String(text.prefix(CoverChoice.maxTitleLength)) }
                    }
                    .accessibilityIdentifier("cover.titleField")
                Spacer()
            }
        }
        .onAppear { titleFocused = true }
    }

    private func startEditing() {
        typing = choice.title
        isEditingTitle = true
    }

    private func finishEditing() {
        choice.setTitle(typing)
        titleFocused = false
        isEditingTitle = false
    }

    private func save() {
        isSaving = true
        let final = choice
        Task {
            let image = final.isCustom ? await CoverRenderer.image(video: video, choice: final) : nil
            onSave(final, image)
        }
    }

    private func loadFrames() async {
        for time in frameTimes {
            guard frames[time] == nil else { continue }
            if let image = await CoverRenderer.frame(of: video, at: time, maximumSize: CGSize(width: 160, height: 284)) {
                frames[time] = UIImage(cgImage: image)
            }
        }
    }
}
