import UIKit

// Story « nouvelle photo de profil » (ADR-056), dessinée par l'app en 1080×1920 : fond gris dégradé, « ✨ J'ai une
// nouvelle photo de profil », la photo ronde cerclée de blanc, @pseudo et la date. Publiée ensuite comme une story photo
// (même préparation : `PrepareStoryPhotoUseCase`, sans métadonnées).
enum ProfilePhotoStory {
    static let size = CGSize(width: 1080, height: 1920)

    static func render(avatar: UIImage, username: String, date: Date) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(white: 0.55, alpha: 1).cgColor, UIColor(white: 0.36, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            draw("✨ J’ai une nouvelle photo de profil", font: .systemFont(ofSize: 72, weight: .bold), color: .white, top: 470, height: 200)

            let diameter: CGFloat = 640
            let circle = CGRect(x: (size.width - diameter) / 2, y: 720, width: diameter, height: diameter)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: circle.insetBy(dx: -16, dy: -16)).fill()
            context.cgContext.saveGState()
            UIBezierPath(ovalIn: circle).addClip()
            avatar.draw(in: circle)
            context.cgContext.restoreGState()

            draw("@\(username)", font: .systemFont(ofSize: 80, weight: .bold), color: UIColor(white: 1, alpha: 0.9), top: 1420, height: 110)
            let day = date.formatted(.dateTime.day().month(.twoDigits).year())
            draw(day, font: .systemFont(ofSize: 52, weight: .semibold), color: UIColor(white: 1, alpha: 0.75), top: 1540, height: 80)
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    private static func draw(_ text: String, font: UIFont, color: UIColor, top: CGFloat, height: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        (text as NSString).draw(in: CGRect(x: 80, y: top, width: size.width - 160, height: height), withAttributes: attributes)
    }
}
