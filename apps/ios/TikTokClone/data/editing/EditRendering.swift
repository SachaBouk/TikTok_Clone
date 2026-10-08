import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// Rendu d'une image de la vidéo modifiée (ADR-052) : fonctions pures sur des `CIImage`, testées sans export.
enum EditRendering {
    // Image d'origine → image finale : rotation du segment, remplissage (centré, rogné), filtre, textes par-dessus.
    static func render(_ frame: CIImage, transform: CGAffineTransform, renderSize: CGSize, filter: VideoFilter, overlay: CIImage?) -> CIImage {
        let filled = fill(oriented(frame, transform: transform), size: renderSize)
        let colored = filtered(filled, filter)
        return overlay.map { $0.composited(over: colored) } ?? colored
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

    // Remplit `size` en gardant les proportions : centrée, rognée sur les bords qui dépassent.
    static func fill(_ image: CIImage, size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (size.width - scaled.extent.width) / 2 - scaled.extent.minX
        let dy = (size.height - scaled.extent.height) / 2 - scaled.extent.minY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: CGRect(origin: .zero, size: size))
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
// Mêmes proportions que l'aperçu SwiftUI (`EditorTextStyle`) : police relative à la largeur, centre relatif.
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(white: overlay.color == .black ? 1 : 0, alpha: 0.6)
        shadow.shadowBlurRadius = style.shadowRadius
        shadow.shadowOffset = .zero
        let rgb = overlay.color.rgb
        let text = NSAttributedString(
            string: overlay.text,
            attributes: [
                .font: UIFont.systemFont(ofSize: style.fontSize, weight: .heavy),
                .foregroundColor: UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1),
                .paragraphStyle: paragraph,
                .shadow: shadow,
            ])
        let bounds = text.boundingRect(
            with: CGSize(width: style.maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        let height = bounds.height.rounded(.up)
        let origin = CGPoint(x: overlay.center.x * size.width - style.maxWidth / 2, y: overlay.center.y * size.height - height / 2)
        text.draw(with: CGRect(origin: origin, size: CGSize(width: style.maxWidth, height: height)), options: [.usesLineFragmentOrigin], context: nil)
    }
}

// Proportions d'un texte pour une image de largeur `width` : partagées par l'export et l'aperçu.
struct EditorTextStyle {
    let fontSize: CGFloat
    let maxWidth: CGFloat
    let shadowRadius: CGFloat

    init(overlay: TextOverlay, width: CGFloat) {
        fontSize = width * overlay.size.relativeFontSize
        maxWidth = width * 0.9
        shadowRadius = max(1, width * 0.008)
    }
}
