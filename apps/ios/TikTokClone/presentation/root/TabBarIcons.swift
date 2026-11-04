import UIKit

// Icônes de la barre d'onglets, dessinées comme celles de TikTok (choix du développeur, d'après une capture) : maison
// arrondie avec sa porte, deux personnes, bulle de message avec un trait, personne ; contour quand l'onglet n'est pas
// sélectionné, pleine quand il l'est. Images en gabarit : la barre native leur donne sa teinte. Le « + » de la création
// garde ses couleurs (`createButton`).
enum TabBarIcon {
    case home, friends, inbox, profile

    static let canvas = CGSize(width: 28, height: 28)
    private static let lineWidth: CGFloat = 2.1

    // Nom passé à `TabRefreshIcon` pour dessiner l'icône pleine d'un onglet de feed pendant son rechargement.
    var refreshName: String {
        switch self {
        case .home: "tab.home"
        case .friends: "tab.friends"
        case .inbox: "tab.inbox"
        case .profile: "tab.profile"
        }
    }

    static func named(_ name: String) -> TabBarIcon? {
        [.home, .friends, .inbox, .profile].first { $0.refreshName == name }
    }

    @MainActor
    func image(filled: Bool) -> UIImage {
        let image = UIGraphicsImageRenderer(size: Self.canvas).image { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            UIColor.black.setStroke()
            switch self {
            case .home: Self.drawHome(cg, filled: filled)
            case .friends: Self.drawFriends(filled: filled)
            case .inbox: Self.drawInbox(cg, filled: filled)
            case .profile: Self.drawProfile(filled: filled)
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    // « + » de la création : touche arrondie débordant en cyan à gauche et en rose à droite ; blanche à « + » noir sur une
    // barre sombre, noire à « + » blanc sur une barre claire (comme TikTok), selon l'apparence de la barre.
    @MainActor
    static func createButton() -> UIImage {
        // Chaque version garde l'échelle de l'écran (sans elle, l'image était dessinée trois fois trop grande).
        let asset = UIImageAsset()
        for (style, key, plus) in [(UIUserInterfaceStyle.dark, UIColor.white, UIColor.black), (.light, .black, .white)] {
            let image = createButton(key: key, plus: plus)
            let traits = UITraitCollection {
                $0.userInterfaceStyle = style
                $0.displayScale = image.scale
            }
            asset.register(image, with: traits)
        }
        return asset.image(
            with: UITraitCollection {
                $0.userInterfaceStyle = .dark
                $0.displayScale = UITraitCollection.current.displayScale
            })
    }

    @MainActor
    private static func createButton(key keyColor: UIColor, plus plusColor: UIColor) -> UIImage {
        let size = CGSize(width: 46, height: 30)
        let key = CGRect(x: 4.5, y: 1, width: 37, height: 28)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.40, green: 0.85, blue: 0.93, alpha: 1).setFill()
            UIBezierPath(roundedRect: key.offsetBy(dx: -4, dy: 0), cornerRadius: 9).fill()
            UIColor(red: 0.93, green: 0.21, blue: 0.40, alpha: 1).setFill()
            UIBezierPath(roundedRect: key.offsetBy(dx: 4, dy: 0), cornerRadius: 9).fill()
            keyColor.setFill()
            UIBezierPath(roundedRect: key, cornerRadius: 9).fill()
            let plus = UIBezierPath()
            plus.move(to: CGPoint(x: key.midX - 7.5, y: key.midY))
            plus.addLine(to: CGPoint(x: key.midX + 7.5, y: key.midY))
            plus.move(to: CGPoint(x: key.midX, y: key.midY - 7.5))
            plus.addLine(to: CGPoint(x: key.midX, y: key.midY + 7.5))
            plus.lineWidth = 2.8
            plus.lineCapStyle = .round
            plusColor.setStroke()
            plus.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    // MARK: Dessins (repère de 28 × 28)

    // Polygone aux coins arrondis.
    private static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> UIBezierPath {
        let count = points.count
        let start = CGPoint(x: (points[count - 1].x + points[0].x) / 2, y: (points[count - 1].y + points[0].y) / 2)
        let cg = CGMutablePath()
        cg.move(to: start)
        for index in 0..<count {
            cg.addArc(tangent1End: points[index], tangent2End: points[(index + 1) % count], radius: radius)
        }
        cg.closeSubpath()
        return UIBezierPath(cgPath: cg)
    }

    private static func drawHome(_ cg: CGContext, filled: Bool) {
        let house = roundedPolygon(
            [CGPoint(x: 14, y: 1.8), CGPoint(x: 24.5, y: 10.8), CGPoint(x: 24.5, y: 24.5), CGPoint(x: 3.5, y: 24.5), CGPoint(x: 3.5, y: 10.8)],
            radius: 3.2)
        let door = UIBezierPath(roundedRect: CGRect(x: 12.7, y: 14.5, width: 2.6, height: 7), cornerRadius: 1.3)
        if filled {
            house.fill()
            cg.setBlendMode(.clear)
            door.fill()
            cg.setBlendMode(.normal)
        } else {
            house.lineWidth = lineWidth
            house.lineJoinStyle = .round
            house.stroke()
            door.fill()
        }
    }

    // Buste arrondi : du bas gauche au bas droit, en dôme.
    private static func bust(minX: CGFloat, maxX: CGFloat, top: CGFloat, bottom: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: minX, y: bottom))
        path.addLine(to: CGPoint(x: minX, y: bottom - 1.5))
        path.addCurve(
            to: CGPoint(x: maxX, y: bottom - 1.5), controlPoint1: CGPoint(x: minX, y: top - 1), controlPoint2: CGPoint(x: maxX, y: top - 1))
        path.addLine(to: CGPoint(x: maxX, y: bottom))
        path.close()
        return path
    }

    private static func draw(_ path: UIBezierPath, filled: Bool) {
        if filled {
            path.fill()
        } else {
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private static func drawFriends(filled: Bool) {
        // Personne de devant (à gauche), puis celle de derrière (à droite), plus petite.
        draw(UIBezierPath(ovalIn: CGRect(x: 6.3, y: 4, width: 9, height: 9)), filled: filled)
        draw(bust(minX: 2.5, maxX: 19, top: 15.5, bottom: 24), filled: filled)
        draw(UIBezierPath(ovalIn: CGRect(x: 17.2, y: 5.5, width: 6.6, height: 6.6)), filled: filled)
        let back = UIBezierPath()
        back.move(to: CGPoint(x: 20.5, y: 15.2))
        back.addCurve(to: CGPoint(x: 25.6, y: 21.5), controlPoint1: CGPoint(x: 23.6, y: 15.4), controlPoint2: CGPoint(x: 25.6, y: 17.8))
        back.addLine(to: CGPoint(x: 25.6, y: 24))
        back.addLine(to: CGPoint(x: 22, y: 24))
        if filled {
            back.addLine(to: CGPoint(x: 22, y: 21))
            back.addCurve(to: CGPoint(x: 20.5, y: 15.2), controlPoint1: CGPoint(x: 22, y: 18.5), controlPoint2: CGPoint(x: 21.4, y: 16.6))
            back.close()
        }
        draw(back, filled: filled)
    }

    private static func drawInbox(_ cg: CGContext, filled: Bool) {
        let bubble = UIBezierPath(roundedRect: CGRect(x: 3.5, y: 4.5, width: 21, height: 15.5), cornerRadius: 5)
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: 6.5, y: 19))
        tail.addLine(to: CGPoint(x: 6.5, y: 24.5))
        tail.addLine(to: CGPoint(x: 12, y: 19.5))
        let line = UIBezierPath()
        line.move(to: CGPoint(x: 10, y: 12.3))
        line.addLine(to: CGPoint(x: 18, y: 12.3))
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        if filled {
            bubble.fill()
            tail.close()
            tail.fill()
            cg.setBlendMode(.clear)
            line.stroke()
            cg.setBlendMode(.normal)
        } else {
            bubble.lineWidth = lineWidth
            bubble.stroke()
            // Queue : par-dessus le bas de la bulle, dont le trait est effacé à cet endroit.
            cg.setBlendMode(.clear)
            UIBezierPath(rect: CGRect(x: 7.6, y: 18.8, width: 3.4, height: 2.4)).fill()
            cg.setBlendMode(.normal)
            tail.lineWidth = lineWidth
            tail.lineJoinStyle = .round
            tail.lineCapStyle = .round
            tail.stroke()
            line.stroke()
        }
    }

    private static func drawProfile(filled: Bool) {
        draw(UIBezierPath(ovalIn: CGRect(x: 8.5, y: 3.5, width: 11, height: 11)), filled: filled)
        draw(bust(minX: 5, maxX: 23, top: 16.5, bottom: 24.5), filled: filled)
    }
}
