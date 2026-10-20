import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// Rendu d'une image de la vidéo modifiée (ADR-052, ADR-062) : fonctions pures sur des `CIImage`, testées sans export.
enum EditRendering {
    // Image d'origine → image finale : rotation de la piste, quarts de tour du clip, cadre, image ajustée dans le 9:16
    // (bandes noires, comme TikTok), filtre (à son intensité), effets actifs à cet instant, textes et autocollants par-dessus.
    static func render(
        _ frame: CIImage, transform: CGAffineTransform, quarterTurns: Int = 0, crop: CropRect = .full, renderSize: CGSize, filter: VideoFilter,
        filterIntensity: Double = 1, effects: [VideoEffect] = [], time: Double = 0, overlay: CIImage?
    ) -> CIImage {
        let turned = rotated(oriented(frame, transform: transform), quarterTurns: quarterTurns)
        let fitted = fit(cropped(turned, to: crop), size: renderSize)
        var image = filtered(fitted, filter, intensity: filterIntensity)
        for effect in effects { image = effected(image, effect, time: time) }
        return overlay.map { $0.composited(over: image) } ?? image
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

    // Filtre mélangé à l'image d'origine selon son intensité (0 : image d'origine, 1 : filtre entier).
    static func filtered(_ image: CIImage, _ filter: VideoFilter, intensity: Double = 1) -> CIImage {
        guard filter != .none, intensity > 0 else { return image }
        let full = fullyFiltered(image, filter).cropped(to: image.extent)
        guard intensity < 1 else { return full }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = image
        mix.targetImage = full
        mix.time = Float(intensity)
        return mix.outputImage?.cropped(to: image.extent) ?? full
    }

    private static func fullyFiltered(_ image: CIImage, _ filter: VideoFilter) -> CIImage {
        switch filter {
        case .none:
            return image
        case .mono:
            return photoEffect(image, CIFilter.photoEffectMono())
        case .warm, .cool:
            // Point blanc déplacé : une image vue comme plus froide qu'elle n'est est réchauffée, et inversement.
            return temperature(image, target: filter == .warm ? 5000 : 8500)
        case .vivid:
            return controls(image, saturation: 1.4, contrast: 1.08)
        case .vintage:
            return photoEffect(image, CIFilter.photoEffectTransfer())
        case .fade:
            return photoEffect(image, CIFilter.photoEffectFade())
        case .instant:
            return photoEffect(image, CIFilter.photoEffectInstant())
        case .noir:
            return photoEffect(image, CIFilter.photoEffectNoir())
        case .chrome:
            return photoEffect(image, CIFilter.photoEffectChrome())
        case .natural:
            return controls(image, saturation: 1.05, contrast: 1.03, brightness: 0.01)
        case .sunny:
            return temperature(exposure(image, 0.25), target: 5800)
        case .vitality:
            return vibrance(image, 0.7)
        case .warmth:
            return vibrance(temperature(image, target: 5300), 0.2)
        case .soft:
            let shadows = CIFilter.highlightShadowAdjust()
            shadows.inputImage = image
            shadows.shadowAmount = 0.5
            shadows.highlightAmount = 0.9
            return controls(shadows.outputImage ?? image, saturation: 0.9)
        case .holiday:
            return vibrance(controls(image, saturation: 1.35, contrast: 1.05), 0.3)
        case .forest:
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            matrix.rVector = CIVector(x: 0.95, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: 1.08, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: 0.95, w: 0)
            return controls(matrix.outputImage ?? image, contrast: 1.05)
        case .chill:
            return controls(temperature(image, target: 7800), saturation: 0.85, brightness: 0.02)
        case .dusk:
            return vignette(controls(temperature(image, target: 4800), contrast: 1.12), intensity: 0.6)
        case .california:
            return exposure(temperature(vibrance(image, 0.5), target: 5600), 0.1)
        case .tasty:
            return temperature(vibrance(image, 0.6), target: 5600)
        case .crisp:
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = image
            sharpen.sharpness = 0.6
            return controls(sharpen.outputImage ?? image, contrast: 1.1)
        case .fresh:
            return temperature(controls(image, saturation: 1.15, brightness: 0.03), target: 7000)
        case .golden:
            return exposure(temperature(image, target: 4500), 0.1)
        }
    }

    // Effet visuel (ADR-063) sur une image de la vidéo finale ; `time` (secondes) anime le bruit.
    static func effected(_ image: CIImage, _ effect: VideoEffect, time: Double = 0) -> CIImage {
        let extent = image.extent
        let width = extent.width
        let center = CIVector(x: extent.midX, y: extent.midY)
        let output: CIImage?
        switch effect {
        case .overExposure:
            output = exposure(image, 1.5)
        case .blackNoise:
            let noir = photoEffect(image, CIFilter.photoEffectNoir())
            let shift = CGAffineTransform(
                translationX: CGFloat((time * 977).truncatingRemainder(dividingBy: 512)),
                y: CGFloat((time * 613).truncatingRemainder(dividingBy: 512)))
            let noise = controls(
                (CIFilter.randomGenerator().outputImage ?? image).transformed(by: shift).cropped(to: extent), saturation: 0, brightness: -0.2)
            let blend = CIFilter.softLightBlendMode()
            blend.inputImage = noise
            blend.backgroundImage = noir
            output = blend.outputImage
        case .blur:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image.clampedToExtent()
            blur.radius = Float(width * 0.025)
            output = blur.outputImage
        case .glow:
            let bloom = CIFilter.bloom()
            bloom.inputImage = image.clampedToExtent()
            bloom.radius = Float(width * 0.03)
            bloom.intensity = 1
            output = bloom.outputImage
        case .vignette:
            output = vignette(image, intensity: 1)
        case .negative:
            // Inversé en sRGB (dans l'espace linéaire de Core Image, le négatif serait délavé).
            let invert = CIFilter.colorInvert()
            invert.inputImage = image.applyingFilter("CILinearToSRGBToneCurve")
            output = invert.outputImage?.applyingFilter("CISRGBToneCurveToLinear")
        case .retroBlue:
            let falseColor = CIFilter.falseColor()
            falseColor.inputImage = image
            falseColor.color0 = CIColor(red: 0.04, green: 0.07, blue: 0.3)
            falseColor.color1 = CIColor(red: 0.6, green: 0.9, blue: 1)
            output = falseColor.outputImage
        case .posterize:
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = image
            posterize.levels = 4
            output = posterize.outputImage
        case .comic:
            let comic = CIFilter.comicEffect()
            comic.inputImage = image
            output = comic.outputImage
        case .pixelate:
            let pixels = CIFilter.pixellate()
            pixels.inputImage = image.clampedToExtent()
            pixels.center = CGPoint(x: extent.midX, y: extent.midY)
            pixels.scale = Float(max(4, width / 36))
            output = pixels.outputImage
        case .mirror:
            // Moitié gauche reflétée à droite.
            let half = image.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: extent.width / 2, height: extent.height))
            let flipped = half.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -(extent.minX * 2 + extent.width), y: 0))
            output = flipped.composited(over: image)
        case .twirl:
            let twirl = CIFilter.twirlDistortion()
            twirl.inputImage = image.clampedToExtent()
            twirl.center = CGPoint(x: center.x, y: center.y)
            twirl.radius = Float(width * 0.6)
            twirl.angle = .pi
            output = twirl.outputImage
        case .bump:
            let bump = CIFilter.bumpDistortion()
            bump.inputImage = image.clampedToExtent()
            bump.center = CGPoint(x: center.x, y: center.y)
            bump.radius = Float(width * 0.45)
            bump.scale = 0.6
            output = bump.outputImage
        }
        return output?.cropped(to: extent) ?? image
    }

    private static func photoEffect(_ image: CIImage, _ effect: some CIFilter & CIPhotoEffect) -> CIImage {
        effect.inputImage = image
        return effect.outputImage ?? image
    }

    private static func temperature(_ image: CIImage, target: CGFloat) -> CIImage {
        let effect = CIFilter.temperatureAndTint()
        effect.inputImage = image
        effect.neutral = CIVector(x: 6500, y: 0)
        effect.targetNeutral = CIVector(x: target, y: 0)
        return effect.outputImage ?? image
    }

    private static func controls(_ image: CIImage, saturation: Float = 1, contrast: Float = 1, brightness: Float = 0) -> CIImage {
        let effect = CIFilter.colorControls()
        effect.inputImage = image
        effect.saturation = saturation
        effect.contrast = contrast
        effect.brightness = brightness
        return effect.outputImage ?? image
    }

    private static func vibrance(_ image: CIImage, _ amount: Float) -> CIImage {
        let effect = CIFilter.vibrance()
        effect.inputImage = image
        effect.amount = amount
        return effect.outputImage ?? image
    }

    private static func exposure(_ image: CIImage, _ ev: Float) -> CIImage {
        let effect = CIFilter.exposureAdjust()
        effect.inputImage = image
        effect.ev = ev
        return effect.outputImage ?? image
    }

    private static func vignette(_ image: CIImage, intensity: Float) -> CIImage {
        let effect = CIFilter.vignetteEffect()
        effect.inputImage = image
        effect.center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        effect.radius = Float(max(image.extent.width, image.extent.height) * 0.55)
        effect.intensity = intensity
        effect.falloff = 0.5
        return effect.outputImage ?? image
    }
}

// Textes et autocollants posés sur la vidéo, dessinés une fois par export dans une image transparente de la taille de la
// vidéo.
// Même mise en page que l'aperçu SwiftUI (`EditorTextStyle`) : police relative à la largeur, centre relatif.
enum TextOverlayRenderer {
    static func image(_ texts: [TextOverlay], stickers: [StickerOverlay] = [], size: CGSize) -> CIImage? {
        guard !texts.isEmpty || !stickers.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // Autocollants sous les textes, comme dans l'aperçu.
            for sticker in stickers { draw(sticker, in: size) }
            for text in texts { draw(text, in: size) }
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }

    private static func draw(_ sticker: StickerOverlay, in size: CGSize) {
        let style = StickerStyle(sticker: sticker, width: size.width)
        let text = style.attributedText(sticker.text)
        let box = style.size(for: sticker.text)
        let origin = CGPoint(x: sticker.center.x * size.width - box.width / 2, y: sticker.center.y * size.height - box.height / 2)
        text.draw(with: CGRect(origin: origin, size: box), options: [.usesLineFragmentOrigin], context: nil)
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

// Mise en page d'un autocollant (ADR-063) pour une image de largeur `width` : partagée par l'export et l'aperçu.
struct StickerStyle {
    let font: UIFont
    let fontSize: CGFloat
    let shadowRadius: CGFloat
    let kind: StickerOverlay.Kind

    init(sticker: StickerOverlay, width: CGFloat) {
        self.init(kind: sticker.kind, scale: sticker.scale, width: width)
    }

    init(kind: StickerOverlay.Kind, scale: Double, width: CGFloat) {
        self.kind = kind
        fontSize = width * kind.baseRelativeSize * scale
        font = Self.font(kind, size: fontSize)
        shadowRadius = kind == .emoji ? 0 : max(1, width * 0.01)
    }

    // Date fine, date condensée, heure à chasse fixe ; emoji dans la police du système.
    static func font(_ kind: StickerOverlay.Kind, size: CGFloat) -> UIFont {
        switch kind {
        case .emoji: .systemFont(ofSize: size)
        case .dateSlash: .systemFont(ofSize: size, weight: .light)
        case .dateDash: UIFont(name: "Futura-CondensedExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .black)
        case .time: .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        }
    }

    func attributedText(_ string: String) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        if kind != .emoji {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor(white: 0, alpha: 0.5)
            shadow.shadowBlurRadius = shadowRadius
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    func size(for string: String) -> CGSize {
        let bounds = attributedText(string).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        return CGSize(width: bounds.width.rounded(.up) + 2, height: bounds.height.rounded(.up))
    }
}

// Vignettes des panneaux de filtres et d'effets (ADR-063) : une image de la vidéo, carrée, filtrée ou avec l'effet.
enum LookThumbnails {
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    static func square(_ image: UIImage, side: CGFloat) -> CIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        let edge = min(extent.width, extent.height)
        let cropped = source.cropped(to: CGRect(x: extent.midX - edge / 2, y: extent.midY - edge / 2, width: edge, height: edge))
        let moved = cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY))
        return moved.transformed(by: CGAffineTransform(scaleX: side / edge, y: side / edge))
    }

    static func filtered(_ base: CIImage, _ filter: VideoFilter) -> UIImage? {
        render(EditRendering.filtered(base, filter))
    }

    static func effected(_ base: CIImage, _ effect: VideoEffect) -> UIImage? {
        render(EditRendering.effected(base, effect, time: 0.5))
    }

    private static func render(_ image: CIImage) -> UIImage? {
        context.createCGImage(image, from: image.extent).map { UIImage(cgImage: $0) }
    }
}
