import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// Rendu d'une image de la vidéo modifiée (ADR-052, ADR-062) : fonctions pures sur des `CIImage`, testées sans export.
enum EditRendering {
    // Image d'origine → image finale : rotation de la piste, quarts de tour du clip, cadre, image ajustée dans le 9:16
    // (bandes noires, comme TikTok), filtre, textes par-dessus.
    static func render(
        _ frame: CIImage, transform: CGAffineTransform, quarterTurns: Int = 0, crop: CropRect = .full, renderSize: CGSize, filter: VideoFilter,
        overlay: CIImage?
    ) -> CIImage {
        let turned = rotated(oriented(frame, transform: transform), quarterTurns: quarterTurns)
        let fitted = fit(cropped(turned, to: crop), size: renderSize)
        let colored = filtered(fitted, filter)
        return overlay.map { $0.composited(over: colored) } ?? colored
    }

    // Quarts de tour dans le sens des aiguilles d'une montre, image ramenée à l'origine.
    static func rotated(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns > 0 else { return image }
        // Core Image : angle positif = sens inverse des aiguilles d'une montre.
        let turned = image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2))
        return turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
    }

    // Cadre relatif (origine en haut à gauche) → rectangle Core Image (origine en bas), image ramenée à l'origine.
    static func cropped(_ image: CIImage, to crop: CropRect) -> CIImage {
        guard !crop.isFull else { return image }
        let extent = image.extent
        let rect = CGRect(
            x: extent.minX + crop.x * extent.width, y: extent.minY + (1 - crop.y - crop.height) * extent.height,
            width: crop.width * extent.width, height: crop.height * extent.height
        ).integral.intersection(extent)
        let kept = image.cropped(to: rect)
        return kept.transformed(by: CGAffineTransform(translationX: -kept.extent.minX, y: -kept.extent.minY))
    }

    // Ajustée dans `size` en gardant les proportions : centrée, sur fond noir.
    static func fit(_ image: CIImage, size: CGSize) -> CIImage {
        let extent = image.extent
        let bounds = CGRect(origin: .zero, size: size)
        let black = CIImage(color: .black).cropped(to: bounds)
        guard extent.width > 0, extent.height > 0 else { return black }
        let scale = min(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (size.width - scaled.extent.width) / 2 - scaled.extent.minX
        let dy = (size.height - scaled.extent.height) / 2 - scaled.extent.minY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).composited(over: black).cropped(to: bounds)
    }

    // Taille affichée d'une piste : sa taille d'origine tournée par sa transformation (une vidéo d'iPhone en portrait
    // est souvent enregistrée couchée, avec un quart de tour).
    static func orientedSize(_ size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
    }

    // Applique la transformation de la piste (exprimée avec l'origine en haut, comme UIKit) à une image Core Image
    // (origine en bas) : retournement vertical, transformation, retournement inverse, puis retour à l'origine.
    static func oriented(_ image: CIImage, transform: CGAffineTransform) -> CIImage {
        let height = image.extent.height
        let toTopDown = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        let linear = CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: 0, ty: 0)
        let toBottomUp = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        let moved = image.transformed(by: toTopDown.concatenating(linear).concatenating(toBottomUp))
        return moved.transformed(by: CGAffineTransform(translationX: -moved.extent.minX, y: -moved.extent.minY))
    }

    static func filtered(_ image: CIImage, _ filter: VideoFilter) -> CIImage {
        let output: CIImage?
        switch filter {
        case .none:
            return image
        case .mono:
            let effect = CIFilter.photoEffectMono()
            effect.inputImage = image
            output = effect.outputImage
        case .warm, .cool:
            // Point blanc déplacé : une image vue comme plus froide qu'elle n'est est réchauffée, et inversement.
            let effect = CIFilter.temperatureAndTint()
            effect.inputImage = image
            effect.neutral = CIVector(x: 6500, y: 0)
            effect.targetNeutral = CIVector(x: filter == .warm ? 5000 : 8500, y: 0)
            output = effect.outputImage
        case .vivid:
            let effect = CIFilter.colorControls()
            effect.inputImage = image
            effect.saturation = 1.4
            effect.contrast = 1.08
            output = effect.outputImage
        case .vintage:
            let effect = CIFilter.photoEffectTransfer()
            effect.inputImage = image
            output = effect.outputImage
        case .fade:
            let effect = CIFilter.photoEffectFade()
            effect.inputImage = image
            output = effect.outputImage
        case .instant:
            let effect = CIFilter.photoEffectInstant()
            effect.inputImage = image
            output = effect.outputImage
        }
        return output?.cropped(to: image.extent) ?? image
    }
}

// Textes posés sur la vidéo, dessinés une fois par export dans une image transparente de la taille de la vidéo.
// Même mise en page que l'aperçu SwiftUI (`EditorTextStyle`) : police relative à la largeur, centre relatif.
enum TextOverlayRenderer {
    static func image(_ texts: [TextOverlay], size: CGSize) -> CIImage? {
        guard !texts.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for text in texts { draw(text, in: size) }
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }

    private static func draw(_ overlay: TextOverlay, in size: CGSize) {
        let style = EditorTextStyle(overlay: overlay, width: size.width)
        let text = style.attributedText(overlay.text, shadow: overlay.style.background == .none)
        let box = style.boxSize(for: overlay.text)
        let frame = CGRect(
            x: overlay.center.x * size.width - box.width / 2, y: overlay.center.y * size.height - box.height / 2, width: box.width,
            height: box.height)
        if let fill = overlay.style.fill {
            let rgb = fill.color.rgb
            UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: fill.opacity).setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: style.cornerRadius).fill()
        }
        let textRect = frame.insetBy(dx: style.horizontalPadding, dy: style.verticalPadding)
        text.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
    }
}

// Mise en page d'un texte pour une image de largeur `width` : partagée par l'export, l'aperçu et l'éditeur de texte.
// La largeur est mesurée par UIKit, pour que les lignes se coupent au même endroit partout.
struct EditorTextStyle {
    let font: UIFont
    let fontSize: CGFloat
    let maxWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let style: TextOverlay.Style

    init(overlay: TextOverlay, width: CGFloat) {
        self.init(style: overlay.style, scale: overlay.scale, width: width)
    }

    init(style: TextOverlay.Style, scale: Double, width: CGFloat) {
        self.style = style
        fontSize = width * TextOverlay.baseRelativeFontSize * scale
        font = Self.font(style.font, size: fontSize)
        horizontalPadding = fontSize * 0.32
        verticalPadding = fontSize * 0.14
        cornerRadius = fontSize * 0.28
        maxWidth = width * 0.9
        shadowRadius = max(1, width * 0.008)
    }

    // Fichiers des polices d'iOS ; la police du système (grasse) si l'un manque.
    static func font(_ font: TextOverlay.Font, size: CGFloat) -> UIFont {
        let name: String? =
            switch font {
            case .classic: nil
            case .elegance: "Didot"
            case .retro: "Georgia-BoldItalic"
            case .vintage: "Baskerville-SemiBold"
            case .handwriting: "Noteworthy-Bold"
            case .postcard: "Copperplate-Bold"
            case .script: "Courier-Bold"
            case .technic: "Futura-CondensedExtraBold"
            }
        return name.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size, weight: .heavy)
    }

    var textAlignment: NSTextAlignment {
        switch style.alignment {
        case .center: .center
        case .left: .left
        case .right: .right
        }
    }

    var textUIColor: UIColor {
        let rgb = style.textColor.rgb
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    func attributedText(_ string: String, shadow: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textUIColor, .paragraphStyle: paragraph]
        if shadow {
            let value = NSShadow()
            value.shadowColor = UIColor(white: style.textColor == .black ? 1 : 0, alpha: 0.6)
            value.shadowBlurRadius = shadowRadius
            value.shadowOffset = .zero
            attributes[.shadow] = value
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    // Taille des lignes, coupées à la largeur maximale moins les marges du fond.
    func textSize(for string: String) -> CGSize {
        // Une ligne vide (texte vide, ou retour à la ligne final) compte pour une ligne.
        let measured = string.isEmpty || string.hasSuffix("\n") ? string + " " : string
        let bounds = attributedText(measured, shadow: false).boundingRect(
            with: CGSize(width: maxWidth - 2 * horizontalPadding, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin],
            context: nil)
        return CGSize(width: bounds.width.rounded(.up), height: bounds.height.rounded(.up))
    }

    // Taille du cadre (texte et marges du fond).
    func boxSize(for string: String) -> CGSize {
        let text = textSize(for: string)
        return CGSize(width: text.width + 2 * horizontalPadding, height: text.height + 2 * verticalPadding)
    }
}
