import SwiftUI

// Recadrage d'un clip (ADR-062) : son image (au début de son intervalle, rotation appliquée), un cadre à quadrillage que
// l'on déplace au doigt et agrandit par ses coins, les proportions (« Libre », 9:16, 16:9, 1:1, 3:4, 4:3), puis
// « Annuler » ou « Enregistrer ».
struct CropRequest: Identifiable {
    let id = UUID()
    let clip: EditClip
    let image: UIImage?
}

struct CropEditorView: View {
    let request: CropRequest
    let onSave: (CropRect, CropRatio) -> Void
    @State private var crop: CropRect
    @State private var ratio: CropRatio
    // Cadre au début d'un geste.
    @State private var gestureBase: CropRect?
    @Environment(\.dismiss) private var dismiss

    init(request: CropRequest, onSave: @escaping (CropRect, CropRatio) -> Void) {
        self.request = request
        self.onSave = onSave
        _crop = State(initialValue: request.clip.crop)
        _ratio = State(initialValue: request.clip.cropRatio)
    }

    // Image tournée des quarts de tour du clip.
    private var image: UIImage? {
        request.image.map { CropImage.rotated($0, quarterTurns: request.clip.quarterTurns) }
    }

    // Proportions de l'image (largeur / hauteur).
    private var frameAspect: Double {
        guard let image, image.size.height > 0 else { return 9.0 / 16.0 }
        return image.size.width / image.size.height
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let fitted = fittedSize(in: geometry.size)
                ZStack {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable()
                        } else {
                            Color(white: 0.2)
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    cropOverlay(size: fitted)
                }
                .frame(width: fitted.width, height: fitted.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .padding(16)
            ratioPicker
                .padding(.vertical, 20)
            HStack {
                Button("Annuler") { dismiss() }
                    .accessibilityIdentifier("crop.cancel")
                Spacer()
                Text("Recadrer").font(.title3.bold())
                Spacer()
                Button("Enregistrer") {
                    onSave(crop, ratio)
                    dismiss()
                }
                .accessibilityIdentifier("crop.save")
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color(white: 0.07).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func fittedSize(in size: CGSize) -> CGSize {
        let aspect = frameAspect
        let width = min(size.width, size.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    // Image assombrie hors du cadre, quadrillage, coins ; glisser à l'intérieur déplace, glisser un coin redimensionne.
    private func cropOverlay(size: CGSize) -> some View {
        let rect = CGRect(x: crop.x * size.width, y: crop.y * size.height, width: crop.width * size.width, height: crop.height * size.height)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Path { path in
                for index in 1...2 {
                    let x = rect.minX + rect.width * Double(index) / 3
                    let y = rect.minY + rect.height * Double(index) / 3
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.6), lineWidth: 1)
            .allowsHitTesting(false)
            Rectangle()
                .stroke(.white, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .offset(x: rect.minX, y: rect.minY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let base = gestureBase ?? crop
                            gestureBase = base
                            crop = CropRules.moved(base, dx: value.translation.width / size.width, dy: value.translation.height / size.height)
                        }
                        .onEnded { _ in gestureBase = nil }
                )
                .accessibilityIdentifier("crop.frame")
            ForEach(CropRules.Corner.allCases, id: \.self) { corner in
                cornerHandle(corner)
                    .position(position(of: corner, in: rect))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let base = gestureBase ?? crop
                                gestureBase = base
                                crop = CropRules.resized(
                                    base, corner: corner, dx: value.translation.width / size.width, dy: value.translation.height / size.height,
                                    ratio: ratio, frameAspect: frameAspect)
                            }
                            .onEnded { _ in gestureBase = nil }
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func position(of corner: CropRules.Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // Coin en L, dans une zone touchable de 44 pt.
    private func cornerHandle(_ corner: CropRules.Corner) -> some View {
        let left = corner == .topLeading || corner == .bottomLeading
        let top = corner == .topLeading || corner == .topTrailing
        return Path { path in
            let x: CGFloat = left ? 22 : 22
            let y: CGFloat = top ? 22 : 22
            let horizontal: CGFloat = left ? 18 : -18
            let vertical: CGFloat = top ? 18 : -18
            path.move(to: CGPoint(x: x + horizontal, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + vertical))
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .square))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var ratioPicker: some View {
        HStack(spacing: 0) {
            ForEach(CropRatio.allCases) { option in
                let selected = option == ratio
                Button {
                    ratio = option
                    crop = CropRules.initial(ratio: option, frameAspect: frameAspect)
                } label: {
                    VStack(spacing: 8) {
                        ratioIcon(option)
                            .stroke(selected ? Color.brandPink : .white, lineWidth: 2)
                            .frame(width: 34, height: 34)
                        Text(option.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selected ? Color.brandPink : .white)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("crop.ratio.\(option.rawValue)")
            }
        }
        .padding(.horizontal, 8)
    }

    // Rectangle aux proportions du choix (deux rectangles imbriqués pour « Libre »).
    private func ratioIcon(_ option: CropRatio) -> Path {
        Path { path in
            let box: CGFloat = 30
            guard let value = option.value else {
                path.addRect(CGRect(x: 4, y: 2, width: box - 4, height: box))
                path.addRect(CGRect(x: 10, y: 8, width: box - 16, height: box - 12))
                return
            }
            let width = value >= 1 ? box : box * value
            let height = value >= 1 ? box / value : box
            path.addRect(CGRect(x: (34 - width) / 2, y: (34 - height) / 2, width: width, height: height))
        }
    }
}

// Image tournée de quarts de tour (sens des aiguilles d'une montre), pour l'écran de recadrage.
enum CropImage {
    static func rotated(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns > 0 else { return image }
        let size = turns % 2 == 0 ? image.size : CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}
