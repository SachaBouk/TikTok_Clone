import CoreGraphics
import Foundation
import Testing

@testable import TikTokClone

// Profil façon TikTok (ADR-056) : recadrage rond de la photo et lien d'app vers un profil.
@Suite("Profil : recadrage de la photo, lien du profil")
struct ProfileDisplayRulesTests {
    @Test("recadrage de départ : l'image remplit le cercle, carré centré sur son petit côté")
    func initialCrop() {
        let crop = AvatarCrop(imageSize: CGSize(width: 1200, height: 1600), side: 300)
        #expect(crop.scale == 0.25)
        #expect(crop.cropRect == CGRect(x: 0, y: 200, width: 1200, height: 1200))
    }

    @Test("déplacement borné : jamais de vide dans le cercle ; zoom entre 1 et 5")
    func bounds() {
        let crop = AvatarCrop(imageSize: CGSize(width: 1200, height: 1600), side: 300)
        // Image affichée en 300×400 : 50 points de marge verticale de chaque côté, aucune horizontale.
        let moved = crop.with(zoom: 1, offset: CGSize(width: 80, height: -500))
        #expect(moved.offset == CGSize(width: 0, height: -50))
        #expect(moved.cropRect == CGRect(x: 0, y: 400, width: 1200, height: 1200))
        #expect(crop.with(zoom: 0.2, offset: .zero).zoom == 1)
        #expect(crop.with(zoom: 9, offset: .zero).zoom == AvatarCrop.maxZoom)
    }

    @Test("zoom : carré plus petit, autour du point affiché au centre")
    func zoom() {
        let crop = AvatarCrop(imageSize: CGSize(width: 1000, height: 1000), side: 200).with(zoom: 2, offset: CGSize(width: 100, height: 0))
        #expect(crop.cropRect == CGRect(x: 0, y: 250, width: 500, height: 500))
    }

    @Test("lien du profil : tiktokclone://users/<pseudo>, pseudo valide seulement")
    func link() {
        let url = ProfileLink.url(for: "lea.martin")
        #expect(url.absoluteString == "tiktokclone://users/lea.martin")
        #expect(ProfileLink.username(from: url) == "lea.martin")
        #expect(ProfileLink.username(from: URL(string: "tiktokclone://users/Lea_M")!) == "lea_m")
        #expect(ProfileLink.username(from: URL(string: "tiktokclone://users/a")!) == nil)
        #expect(ProfileLink.username(from: URL(string: "tiktokclone://videos/lea")!) == nil)
        #expect(ProfileLink.username(from: URL(string: "https://users/lea")!) == nil)
    }
}
