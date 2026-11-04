// Icône de l'app (1024 px) : exactement le logo de l'écran de lancement (`AppLogo`) — le symbole `music.note` en
// graisse « black », doublé de ses échos cyan (en haut à gauche) et rose (en bas à droite), décalés de 5 % et 4 % de
// la taille, sur fond noir. Trois versions : claire, sombre (fond transparent) et teintée.
// Choix du développeur : la licence des SF Symbols interdit leur usage dans une icône d'app ; à remplacer par un
// dessin maison avant une publication sur l'App Store.
// Icônes au choix des abonnés « Plus » (ADR-073) : le même logo dans d'autres couleurs (Or, Néon, Rétro), écrites à côté
// (`AppIconGold.appiconset`…), avec un aperçu de 256 px pour l'écran de choix (`AppIconGoldPreview.imageset`…).
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
func render(name: String, background: NSColor?, layers: [(NSColor, CGFloat, CGFloat)], in directory: String = outDir, pixels: Int = size) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Aperçu : le même dessin, réduit.
    let scale = CGFloat(pixels) / CGFloat(size)
    context.scaleBy(x: scale, y: scale)
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
    let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
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

// Icônes au choix (ADR-073) : fond et couleurs de la note et de ses échos.
let assets = URL(fileURLWithPath: outDir).deletingLastPathComponent().path
let variants: [(name: String, background: NSColor, layers: [(NSColor, CGFloat, CGFloat)])] = [
    ("AppIconGold", color(0x1A, 0x14, 0x08), [(color(0xB8, 0x86, 0x0B), -echoX, echoY), (color(0xFF, 0xE0, 0x82), echoX, -echoY), (color(0xFF, 0xD7, 0x00), 0, 0)]),
    ("AppIconNeon", color(0x14, 0x06, 0x2E), [(color(0x00, 0xFF, 0xF0), -echoX, echoY), (color(0xFF, 0x00, 0xE6), echoX, -echoY), (color(0xF4, 0xEC, 0xFF), 0, 0)]),
    ("AppIconRetro", color(0xF6, 0xE7, 0xC8), [(color(0x2A, 0x9D, 0x8F), -echoX, echoY), (color(0xE7, 0x6F, 0x51), echoX, -echoY), (color(0x26, 0x46, 0x53), 0, 0)]),
]
let manager = FileManager.default
for variant in variants {
    let iconDir = "\(assets)/\(variant.name).appiconset"
    let previewDir = "\(assets)/\(variant.name)Preview.imageset"
    try manager.createDirectory(atPath: iconDir, withIntermediateDirectories: true)
    try manager.createDirectory(atPath: previewDir, withIntermediateDirectories: true)
    render(name: "\(variant.name).png", background: variant.background, layers: variant.layers, in: iconDir)
    render(name: "\(variant.name)Preview.png", background: variant.background, layers: variant.layers, in: previewDir, pixels: 256)
    let icon = #"{"images":[{"filename":"\#(variant.name).png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#
    let preview = #"{"images":[{"filename":"\#(variant.name)Preview.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
    try icon.write(toFile: "\(iconDir)/Contents.json", atomically: true, encoding: .utf8)
    try preview.write(toFile: "\(previewDir)/Contents.json", atomically: true, encoding: .utf8)
}
print("ok")
