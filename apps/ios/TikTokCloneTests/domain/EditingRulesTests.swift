import CoreGraphics
import Foundation
import Testing

@testable import TikTokClone

@Suite("Enregistrement et plan d'édition par clips (ADR-052, ADR-062)")
struct EditingRulesTests {
    private func clip(_ name: String, _ seconds: Double) -> SourceClip {
        SourceClip(file: URL(filePath: "/tmp/\(name).mov"), duration: .milliseconds(Int64(seconds * 1000)))
    }

    @Test("segments : durée cumulée, restant, limite de 3 minutes ou 60 s, segment trop bref ignoré")
    func recordingSession() {
        var session = RecordingSession(kind: .video)
        #expect(session.maxDuration == .seconds(180))
        let appendedA = session.append(clip("a", 100))
        #expect(appendedA)
        let appendedShort = session.append(clip("bref", 0.2))
        #expect(!appendedShort)
        let appendedB = session.append(clip("b", 79.8))
        #expect(appendedB)
        #expect(session.recordedDuration == .milliseconds(179_800))
        #expect(session.remaining == .milliseconds(200))
        #expect(session.isFull)
        #expect(session.progress(including: .seconds(10)) == 1)
        let removedLast = session.removeLast()
        #expect(removedLast == clip("b", 79.8))
        #expect(!session.isFull)
        #expect(abs(session.progress() - 100.0 / 180.0) < 0.0001)
        let removedAll = session.removeAll()
        #expect(removedAll == [clip("a", 100)])
        #expect(session.segments.isEmpty)

        let story = RecordingSession(kind: .story)
        #expect(story.maxDuration == .seconds(60))
    }

    @Test("durée choisie sur la caméra : jamais au-delà de celle de la publication")
    func recordingLimit() {
        #expect(RecordingSession(kind: .video, limit: RecordingLimit.fifteenSeconds.duration).maxDuration == .seconds(15))
        #expect(RecordingSession(kind: .story, limit: RecordingLimit.threeMinutes.duration).maxDuration == .seconds(60))
        #expect(RecordingLimit.allCases.map(\.title) == ["3 min", "60 s", "15 s"])
    }

    @Test("plan : vidéo trop longue raccourcie à la durée maximale, durée finale avec la vitesse de chaque clip")
    func initialTrimAndSpeed() {
        var plan = EditPlan(clips: [clip("a", 200), clip("b", 40)], kind: .video)
        #expect(plan.clips.map(\.keptDuration) == [.seconds(180), .seconds(40)])
        #expect(plan.isTrimmed)
        #expect(plan.outputDuration == .seconds(220))
        #expect(plan.problem == "Une vidéo dure 3 minutes au plus. Raccourcis-la.")
        let first = plan.clips[0].id
        plan.setSpeed(2, of: first)
        #expect(plan.outputDuration == .seconds(130))
        #expect(plan.problem == nil)
        plan.setSpeed(20, of: first)
        #expect(plan.clips[0].speed == 10)
        plan.setSpeedForAll(0.01)
        #expect(plan.clips.map(\.speed) == [0.1, 0.1])
        #expect(plan.commonSpeed == 0.1)
        plan.setSpeed(1, of: first)
        #expect(plan.commonSpeed == nil)

        let story = EditPlan(clips: [clip("s", 61.5)], kind: .story)
        #expect(story.clips[0].end == .seconds(60))
        #expect(!EditPlan(clips: [clip("s", 30)], kind: .story).isTrimmed)
    }

    @Test("curseur de vitesse : repères 0,1x, 1x, 2x, 5x, 10x à intervalles égaux, valeur au dixième")
    func speedScale() {
        #expect(SpeedScale.speed(at: 0) == 0.1)
        #expect(SpeedScale.speed(at: 0.25) == 1)
        #expect(SpeedScale.speed(at: 0.5) == 2)
        #expect(SpeedScale.speed(at: 0.75) == 5)
        #expect(SpeedScale.speed(at: 1) == 10)
        #expect(SpeedScale.speed(at: 0.3) == 1.2)
        #expect(SpeedScale.speed(at: 2) == 10)
        #expect(abs(SpeedScale.fraction(of: 1.2) - 0.3) < 0.0001)
        #expect(SpeedScale.fraction(of: 0.1) == 0)
        #expect(SpeedScale.fraction(of: 50) == 1)
        #expect(SpeedScale.label(1.2) == "1,2x")
        #expect(SpeedScale.label(10) == "10x")
    }

    @Test("à une seconde près, comme le worker (ADR-040)")
    func tolerance() {
        #expect(!PublicationKind.video.isTooLong(.milliseconds(181_000)))
        #expect(PublicationKind.video.isTooLong(.milliseconds(181_001)))
        #expect(!PublicationKind.story.isTooLong(.seconds(61)))
        #expect(PublicationKind.story.isTooLong(.milliseconds(61_001)))
    }

    @Test("découpage d'un clip : bornes dans son fichier, au moins 0,1 s gardée")
    func trimBounds() {
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        let id = plan.clips[0].id
        plan.setStart(.seconds(9.95), of: id)
        #expect(plan.clips[0].start == .milliseconds(9_900))
        plan.setEnd(.seconds(2), of: id)
        #expect(plan.clips[0].end == .seconds(10))
        plan.setStart(.seconds(-3), of: id)
        #expect(plan.clips[0].start == .zero)
        plan.setEnd(.seconds(4), of: id)
        #expect(plan.clips[0].end == .seconds(4))
        plan.setEnd(.seconds(50), of: id)
        #expect(plan.clips[0].end == .seconds(10))

        let short = EditPlan(clips: [clip("court", 0.5)], kind: .video)
        #expect(short.problem == "La vidéo doit durer au moins 1 seconde.")
        #expect(EditPlan(clips: [], kind: .video).problem == "Aucune vidéo.")
    }

    @Test("réencodage seulement s'il le faut : un seul clip seulement découpé est recopié")
    func reencoding() {
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        let id = plan.clips[0].id
        #expect(!plan.needsReencoding)
        plan.setStart(.seconds(2), of: id)
        #expect(!plan.needsReencoding)
        plan.filter = .mono
        #expect(plan.needsReencoding)
        plan.filter = .none
        plan.setSpeed(1.5, of: id)
        #expect(plan.needsReencoding)
        plan.setSpeed(1, of: id)
        plan.setVolume(0.5, of: id)
        #expect(plan.needsReencoding)
        plan.setVolume(1, of: id)
        plan.rotate(id)
        #expect(plan.needsReencoding)
        for _ in 0..<3 { plan.rotate(id) }
        plan.setCrop(CropRect(x: 0, y: 0, width: 0.5, height: 1), ratio: .free, of: id)
        #expect(plan.needsReencoding)
        plan.setCrop(.full, ratio: .free, of: id)
        #expect(!plan.needsReencoding)
        plan.addText("Salut")
        #expect(plan.needsReencoding)
        #expect(EditPlan(clips: [clip("a", 1), clip("b", 1)], kind: .video).needsReencoding)
    }

    @Test("diviser à la tête de lecture, supprimer (jamais le dernier), ajouter au bout")
    func splitDeleteAppend() {
        var plan = EditPlan(clips: [clip("a", 4), clip("b", 6)], kind: .video)
        plan.setSpeed(2, of: plan.clips[1].id)
        // 4 s de « a », puis « b » à 2× (3 s) : l'instant 5,5 s tombe à 3 s dans « b ».
        let split = plan.split(at: .milliseconds(5_500))
        #expect(split)
        #expect(plan.clips.count == 3)
        #expect(plan.clips[1].start == .zero && plan.clips[1].end == .seconds(3))
        #expect(plan.clips[2].start == .seconds(3) && plan.clips[2].end == .seconds(6) && plan.clips[2].speed == 2)
        #expect(plan.clips[1].id != plan.clips[2].id)
        #expect(plan.outputDuration == .seconds(7))
        // Trop près d'un bord : refusé.
        let atEdge = plan.split(at: .milliseconds(4_010))
        #expect(!atEdge)
        #expect(plan.sources == [clip("a", 4), clip("b", 6)])

        let removed = plan.removeClip(plan.clips[0].id)
        #expect(removed)
        var single = EditPlan(clips: [clip("a", 4)], kind: .video)
        let removedLast = single.removeClip(single.clips[0].id)
        #expect(!removedLast)
        single.append([clip("c", 2)])
        #expect(single.clips.map(\.source) == [clip("a", 4), clip("c", 2)])
    }

    @Test("instant de la vidéo finale → clip et instant de son fichier")
    func locate() throws {
        var plan = EditPlan(clips: [clip("a", 4), clip("b", 6)], kind: .video)
        plan.setStart(.seconds(1), of: plan.clips[1].id)
        plan.setSpeed(0.5, of: plan.clips[1].id)
        let start = try #require(plan.locate(.seconds(1)))
        #expect(start.index == 0 && start.sourceTime == .seconds(1))
        // « b » commence à 4 s et dure 10 s (5 s à 0,5×) : 6 s → 1 s + 2 s × 0,5.
        let second = try #require(plan.locate(.seconds(6)))
        #expect(second.index == 1 && second.sourceTime == .seconds(2))
        let end = try #require(plan.locate(.seconds(30)))
        #expect(end.index == 1 && end.sourceTime == .seconds(6))
        #expect(plan.startTime(ofClipAt: 1) == .seconds(4))
    }

    @Test("volume, rotation (cadre remis à l'image entière), recadrage borné, son coupé")
    func clipSettings() {
        var plan = EditPlan(clips: [clip("a", 4), clip("b", 6)], kind: .video)
        let id = plan.clips[0].id
        plan.setVolume(1.5, of: id)
        #expect(plan.clips[0].volume == 1)
        plan.setVolumeForAll(0.3)
        #expect(plan.clips.map(\.volume) == [0.3, 0.3])
        plan.setCrop(CropRect(x: 0.9, y: -1, width: 0.5, height: 0.01), ratio: .square, of: id)
        #expect(plan.clips[0].crop == CropRect(x: 0.5, y: 0, width: 0.5, height: CropRules.minSize))
        #expect(plan.clips[0].cropRatio == .square)
        plan.rotate(id)
        #expect(plan.clips[0].quarterTurns == 1 && plan.clips[0].crop.isFull && plan.clips[0].cropRatio == .free)
        for _ in 0..<3 { plan.rotate(id) }
        #expect(plan.clips[0].quarterTurns == 0)
        plan.isMuted = true
        #expect(plan.needsReencoding)
    }

    @Test("cadre : proportions de départ, déplacé et redimensionné sans sortir de l'image")
    func cropRules() {
        // Image 16:9, cadre 9:16 : toute la hauteur, largeur relative (9/16)/(16/9).
        let portrait = CropRules.initial(ratio: .portrait, frameAspect: 16.0 / 9.0)
        #expect(abs(portrait.width - 0.31640625) < 0.0001 && portrait.height == 1)
        #expect(abs(portrait.x - (1 - portrait.width) / 2) < 0.0001)
        let landscape = CropRules.initial(ratio: .landscape, frameAspect: 9.0 / 16.0)
        #expect(landscape.width == 1 && abs(landscape.height - 0.31640625) < 0.0001)
        #expect(CropRules.initial(ratio: .free, frameAspect: 1) == .full)

        let moved = CropRules.moved(CropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), dx: 1, dy: -1)
        #expect(moved == CropRect(x: 0.5, y: 0, width: 0.5, height: 0.5))

        let free = CropRules.resized(.full, corner: .bottomTrailing, dx: -0.5, dy: -0.95, ratio: .free, frameAspect: 1)
        #expect(free == CropRect(x: 0, y: 0, width: 0.5, height: CropRules.minSize))
        // Carré dans une image carrée : la hauteur suit la largeur, coin opposé fixe.
        let square = CropRules.resized(
            CropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), corner: .topLeading, dx: 0.2, dy: 0, ratio: .square, frameAspect: 1)
        #expect(abs(square.width - 0.3) < 0.0001 && abs(square.height - 0.3) < 0.0001)
        #expect(abs(square.x - 0.7) < 0.0001 && abs(square.y - 0.7) < 0.0001)
    }

    @Test("annuler / rétablir : états successifs, rien si rien n'a changé")
    func history() {
        var history = EditHistory<Int>()
        history.record(1, current: 1)
        #expect(!history.canUndo)
        history.record(1, current: 2)
        history.record(2, current: 3)
        let undone = history.undo(3)
        #expect(undone == 2)
        let undoneAgain = history.undo(2)
        #expect(undoneAgain == 1)
        let nothing = history.undo(1)
        #expect(nothing == nil)
        let redone = history.redo(1)
        #expect(redone == 2)
        history.record(2, current: 5)
        #expect(!history.canRedo)
        let last = history.undo(5)
        #expect(last == 2)
    }

    @Test("textes : nettoyés, 80 caractères et 5 au plus, déplacés dans l'image, vidés = retirés")
    func texts() throws {
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        let blank = plan.addText("   ")
        #expect(blank == nil)
        let tooLong = plan.addText(String(repeating: "a", count: 81))
        #expect(tooLong == nil)
        let added = plan.addText("  Bonjour  ", style: TextOverlay.Style(color: .yellow, font: .retro))
        let first = try #require(added)
        #expect(first.text == "Bonjour")
        #expect(first.center == CGPoint(x: 0.5, y: 0.5))
        for index in 2...5 {
            let other = plan.addText("Texte \(index)")
            #expect(other != nil)
        }
        let sixth = plan.addText("Sixième")
        #expect(sixth == nil)

        plan.moveText(first.id, to: CGPoint(x: -1, y: 2))
        #expect(plan.texts[0].center == CGPoint(x: 0.05, y: 0.95))
        let style = TextOverlay.Style(color: .red, font: .technic, background: .solid, alignment: .left)
        let updated = plan.updateText(first.id, text: "Salut", style: style)
        #expect(updated)
        #expect(plan.texts[0].text == "Salut" && plan.texts[0].style == style)
        plan.scaleText(first.id, to: 10)
        #expect(plan.texts[0].scale == TextOverlay.scaleRange.upperBound)
        plan.scaleText(first.id, to: 0)
        #expect(plan.texts[0].scale == TextOverlay.scaleRange.lowerBound)
        let updatedTooLong = plan.updateText(first.id, text: String(repeating: "b", count: 81), style: style)
        #expect(!updatedTooLong)
        #expect(plan.texts[0].text == "Salut")
        let emptied = plan.updateText(first.id, text: "  ", style: style)
        #expect(!emptied)
        #expect(plan.texts.count == 4)
        plan.removeText(plan.texts[0].id)
        #expect(plan.texts.count == 3)
    }

    @Test("style des textes : lettres lisibles sur le fond, « A » et alignement en boucle ; déplacement aimanté, corbeille")
    func textStyleAndDrag() {
        var style = TextOverlay.Style(color: .yellow)
        #expect(style.textColor == .yellow && style.fill == nil)
        style.background = style.background.next
        #expect(style.background == .solid && style.textColor == .black && style.fill?.opacity == 1)
        style.color = .darkBlue
        #expect(style.textColor == .white)
        style.background = style.background.next
        #expect(style.background == .translucent && style.textColor == .white && style.fill?.opacity == 0.55)
        style.color = .white
        #expect(style.textColor == .black)
        #expect(style.background.next == .none)
        #expect(TextOverlay.Alignment.center.next == .left && TextOverlay.Alignment.left.next == .right)
        #expect(TextOverlay.Alignment.right.next == .center)
        #expect(TextOverlay.Color.white.isLight && TextOverlay.Color.cream.isLight && TextOverlay.Color.yellow.isLight)
        #expect(!TextOverlay.Color.gray.isLight && !TextOverlay.Color.green.isLight && !TextOverlay.Color.lavender.isLight)

        let near = TextDragRules.snapped(CGPoint(x: 0.51, y: 0.3))
        #expect(near.center == CGPoint(x: 0.5, y: 0.3) && near.onGuide)
        let far = TextDragRules.snapped(CGPoint(x: 0.6, y: 0.3))
        #expect(far.center == CGPoint(x: 0.6, y: 0.3) && !far.onGuide)
        #expect(TextDragRules.isOverTrash(CGPoint(x: 0.5, y: 0.05)))
        #expect(!TextDragRules.isOverTrash(CGPoint(x: 0.5, y: 0.3)))
        #expect(!TextDragRules.isOverTrash(CGPoint(x: 0.1, y: 0.05)))
    }

    @Test("filtres : chacun dans sa catégorie (sauf « aucun »), intensité de 0 à 1, sans réencodage à 0")
    func filterCatalog() {
        #expect(VideoFilter.none.category == nil)
        for category in VideoFilter.Category.allCases { #expect(category.filters.count >= 4) }
        #expect(VideoFilter.Category.allCases.flatMap(\.filters).count == VideoFilter.allCases.count - 1)
        #expect(VideoFilter.mono.category == .mood && VideoFilter.chill.category == .landscape)
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        plan.filter = .chill
        #expect(plan.needsReencoding)
        plan.setFilterIntensity(-1)
        #expect(plan.filterIntensity == 0 && !plan.needsReencoding)
        plan.setFilterIntensity(3)
        #expect(plan.filterIntensity == 1)
    }

    @Test("autocollants : date et heure figées, 10 au plus, déplacés dans l'image, taille bornée, réencodage")
    func stickers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5)))
        #expect(StickerOverlay.text(for: .dateSlash, at: date, calendar: calendar) == "07/03")
        #expect(StickerOverlay.text(for: .dateDash, at: date, calendar: calendar) == "07-03-26")
        #expect(StickerOverlay.text(for: .time, at: date, calendar: calendar) == "09:05")

        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        #expect(plan.addSticker(.emoji, text: "") == nil)
        let added = plan.addSticker(.emoji, text: "🔥")
        let sticker = try #require(added)
        #expect(plan.needsReencoding)
        plan.moveSticker(sticker.id, to: CGPoint(x: 2, y: -1))
        #expect(plan.stickers[0].center == CGPoint(x: 0.95, y: 0.05))
        plan.scaleSticker(sticker.id, to: 99)
        #expect(plan.stickers[0].scale == StickerOverlay.scaleRange.upperBound)
        for _ in 2...EditPlan.maxStickers { plan.addSticker(.time, text: "09:05") }
        let extra = plan.addSticker(.emoji, text: "✨")
        #expect(extra == nil && plan.stickers.count == EditPlan.maxStickers)
        plan.removeSticker(sticker.id)
        #expect(plan.stickers.count == EditPlan.maxStickers - 1)
        #expect(EmojiCatalog.sections.allSatisfy { !$0.emojis.isEmpty })
    }

    @Test("effets : posés à la tête de lecture pour 2 s, bornés à la vidéo, bords de 0,2 s au moins, 20 au plus, actifs par plage")
    func effects() throws {
        var track = EffectTrack(effects: [], duration: .seconds(5))
        let firstAdded = track.add(.negative, at: .seconds(1))
        let first = try #require(firstAdded)
        #expect(first.start == .seconds(1) && first.end == .seconds(3))
        let lastAdded = track.add(.blur, at: .seconds(10))
        let last = try #require(lastAdded)
        #expect(last.start == .seconds(5) - EffectTrack.minDuration && last.end == .seconds(5))
        track.setStart(.seconds(4), of: first.id)
        #expect(track.effects[0].start == .seconds(3) - EffectTrack.minDuration)
        track.setStart(.seconds(-2), of: first.id)
        #expect(track.effects[0].start == .zero)
        track.setEnd(.zero, of: first.id)
        #expect(track.effects[0].end == EffectTrack.minDuration)
        track.setEnd(.seconds(9), of: first.id)
        #expect(track.effects[0].end == .seconds(5))
        #expect(EffectTrack.active(track.effects, at: .seconds(4.9)) == [.negative, .blur])
        #expect(EffectTrack.active(track.effects, at: .seconds(5)).isEmpty)
        track.remove(first.id)
        #expect(track.effects.map(\.effect) == [.blur])
        for _ in 2...EffectTrack.maxEffects { track.add(.glow, at: .zero) }
        let extra = track.add(.glow, at: .zero)
        #expect(extra == nil)

        // Plan raccourci : les plages au-delà de la fin sont coupées ou retirées.
        var plan = EditPlan(clips: [clip("a", 3)], kind: .video)
        plan.setEffects([
            TimedEffect(id: UUID(), effect: .mirror, start: .seconds(2), end: .seconds(6)),
            TimedEffect(id: UUID(), effect: .twirl, start: .seconds(4), end: .seconds(6)),
        ])
        #expect(plan.effects.count == 1 && plan.effects[0].end == .seconds(3))
        #expect(plan.needsReencoding)
        for category in VideoEffect.Category.allCases { #expect(!category.effects.isEmpty) }
    }

    @Test("voix off : à la tête de lecture, sans chevauchement, jusqu'à la voix suivante ou la fin, 0,3 s au moins")
    func voiceovers() {
        func clip(_ start: Double, _ duration: Double) -> VoiceoverClip {
            VoiceoverClip(id: UUID(), file: URL(filePath: "/tmp/\(start).m4a"), start: .seconds(start), duration: .seconds(duration))
        }
        var track = VoiceoverTrack(clips: [], duration: .seconds(10))
        #expect(track.available(at: .seconds(2)) == .seconds(8))
        let first = track.add(clip(2, 3))
        #expect(first)
        #expect(track.available(at: .seconds(3)) == nil)
        #expect(track.available(at: .seconds(0)) == .seconds(2))
        // Raccourcie à la place disponible (voix suivante à 2 s).
        let second = track.add(clip(0.5, 5))
        #expect(second)
        #expect(track.clips.last?.duration == .seconds(1.5))
        let tooLate = track.add(clip(9.9, 1))
        #expect(!tooLate)
        #expect(track.sorted.map(\.start) == [.seconds(0.5), .seconds(2)])
        let removed = track.removeLast()
        #expect(removed?.start == .seconds(0.5))
        // Plan raccourci : les voix au-delà de la fin sont coupées ou retirées ; plus de voix, plus d'effet.
        let trimmed = VoiceoverTrack(clips: [clip(1, 3), clip(4.8, 2)], duration: .seconds(5))
        #expect(trimmed.clips.map(\.duration) == [.seconds(3)])
        var plan = EditPlan(clips: [self.clip("a", 6)], kind: .video)
        plan.setVoiceovers([clip(1, 2)])
        plan.voiceEffect = .robot
        #expect(plan.voiceovers.count == 1 && plan.needsReencoding)
        plan.setVoiceovers([])
        #expect(plan.voiceEffect == .none)
        for category in VoiceEffect.Category.allCases { #expect(!category.effects.isEmpty) }
        #expect(VoiceEffect.allCases.filter { $0.category == nil } == [.none])
    }

    @Test("son repris : coupe le son d'origine, passage borné à la vidéo, « Récents » sans doublon")
    func chosenSound() {
        let author = UserSummary(id: "u", username: "lea", displayName: "Léa", avatarURL: nil)
        let sound = Sound(
            id: "s1", videoID: "v1", author: author, audioURL: URL(string: "https://cdn/v1/sound.m4a")!, duration: .seconds(30),
            coverURL: URL(string: "https://cdn/v1/thumbnail.jpg")!, usesCount: 3, favorited: false)
        #expect(sound.title == "Son original - lea")
        var plan = EditPlan(clips: [clip("a", 10)], kind: .video)
        plan.setSound(ChosenSound(sound: sound, file: URL(filePath: "/tmp/s1.m4a"), start: .seconds(25)))
        #expect(plan.isMuted && plan.sound?.start == .seconds(20) && plan.needsReencoding)
        plan.setSoundStart(.seconds(-3))
        #expect(plan.sound?.start == .zero)
        plan.setSoundStart(.seconds(12))
        #expect(plan.sound?.start == .seconds(12))
        plan.setSound(nil)
        #expect(!plan.isMuted && plan.sound == nil)
        #expect(ChosenSound.maxStart(soundDuration: .seconds(5), videoDuration: .seconds(10)) == .zero)
        plan.setOriginalVolume(2)
        plan.setAddedVolume(-1)
        #expect(plan.originalVolume == 1 && plan.addedVolume == 0)
        plan.setOriginalVolume(0.5)
        #expect(plan.needsReencoding)

        var recent = RecentSounds(ids: ["a", "b", "a"])
        #expect(recent.ids == ["a", "b"])
        recent.use("b")
        #expect(recent.ids == ["b", "a"])
        for index in 0..<40 { recent.use("x\(index)") }
        #expect(recent.ids.count == RecentSounds.limit && recent.ids.first == "x39")
    }

    @Test("mesure d'audience : source et modifications, jamais le texte")
    func details() {
        var plan = EditPlan(clips: [clip("a", 10), clip("b", 5)], kind: .video)
        plan.setEnd(.seconds(2), of: plan.clips[1].id)
        plan.filter = .warm
        plan.setSpeedForAll(1.5)
        plan.setCrop(CropRect(x: 0, y: 0, width: 0.5, height: 0.5), ratio: .free, of: plan.clips[0].id)
        plan.addText("Secret")
        plan.setFilterIntensity(0.42)
        plan.addSticker(.emoji, text: "🔥")
        plan.setEffects([TimedEffect(id: UUID(), effect: .negative, start: .zero, end: .seconds(1))])
        let properties = PublicationDetails(source: .camera, plan: plan).properties(photo: false)
        #expect(
            properties == [
                "source": .string("camera"), "segments": .int(2), "trimmed": .bool(true), "filter": .string("warm"), "text_count": .int(1),
                "speed": .double(1.5), "cropped": .bool(true), "rotated": .bool(false), "filter_intensity": .int(42),
                "sticker_count": .int(1), "effect_count": .int(1), "voiceover_count": .int(0), "voice_effect": .string("none"),
                "sound_used": .bool(false), "sound_shared": .bool(true), "cover_changed": .bool(false), "cover_title": .bool(false),
                "location_added": .bool(false), "mention_count": .int(0), "ai_generated": .bool(false), "saved_to_device": .bool(false),
            ])
        #expect(PublicationDetails().properties(photo: true) == ["source": .string("gallery")])
        let story = AnalyticsEvent.storyUploadStarted(photo: true, details: PublicationDetails(source: .camera))
        #expect(story.properties == ["source": .string("camera"), "media_type": .string("photo")])
        let video = AnalyticsEvent.uploadStarted(PublicationDetails())
        #expect(video.name == "video_upload_started")
        #expect(video.properties["segments"] == .int(1) && video.properties["trimmed"] == .bool(false))
    }
}
