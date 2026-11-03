// Icône de l'app (1024 px) : exactement le logo de l'écran de lancement (`AppLogo`) — le symbole `music.note` en
// graisse « black », doublé de ses échos cyan (en haut à gauche) et rose (en bas à droite), décalés de 5 % et 4 % de
// la taille, sur fond noir. Trois versions : claire, sombre (fond transparent) et teintée.
// Choix du développeur : la licence des SF Symbols interdit leur usage dans une icône d'app ; à remplacer par un
// dessin maison avant une publication sur l'App Store.
// Usage (macOS) : swift scripts/make-icon.swift TikTokClone/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = CommandLine.arguments[1]
// Taille de la note (comme la taille de police de `AppLogo`), et décalage de ses échos.
let pointSize: CGFloat = 560
let echoX = pointSize * 0.05
let echoY = pointSize * 0.04

func color(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

func note(_ fill: NSColor) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .black)
        .applying(NSImage.SymbolConfiguration(paletteColors: [fill]))
    return NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
}

// Couches de bas en haut : (couleur, décalage horizontal, décalage vertical vers le haut).
func render(name: String, background: NSColor?, layers: [(NSColor, CGFloat, CGFloat)]) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let background {
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (fill, dx, dy) in layers {
        let image = note(fill)
        // Note centrée dans l'icône, comme dans le `ZStack` du logo.
        let origin = CGPoint(x: (CGFloat(size) - image.size.width) / 2 + dx, y: (CGFloat(size) - image.size.height) / 2 + dy)
        image.draw(in: CGRect(origin: origin, size: image.size))
    }
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

let cyan = color(0x25, 0xF4, 0xEE)
let pink = color(0xFE, 0x2C, 0x55)
let white = color(255, 255, 255)
let black = color(0, 0, 0)
// Cyan en haut à gauche, rose en bas à droite, la note blanche par-dessus (même ordre que `AppLogo`).
let colored: [(NSColor, CGFloat, CGFloat)] = [(cyan, -echoX, echoY), (pink, echoX, -echoY), (white, 0, 0)]

render(name: "AppIcon.png", background: black, layers: colored)
render(name: "AppIcon-Dark.png", background: nil, layers: colored)
// Teintée : niveaux de gris sur fond noir, iOS applique la teinte choisie.
render(name: "AppIcon-Tinted.png", background: black, layers: [(color(150, 150, 150), -echoX, echoY), (color(110, 110, 110), echoX, -echoY), (white, 0, 0)])
print("ok")
