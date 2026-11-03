import AVKit
import SwiftUI

// Menu d'une vidéo (ADR-067), ouvert par un appui long au milieu de la vidéo, comme TikTok : feuille gris clair, cartes
// blanches arrondies. Télécharger (grisé si l'auteur l'interdit), Pas intéressé(e), Signaler (vidéo d'un autre) ;
// Vitesse, Alléger l'affichage, Défilement automatique ; Diffuser (AirPlay). Les actions qui ouvrent autre chose
// (téléchargement, signalement, affichage allégé) ferment d'abord la feuille.
struct VideoMenuSheet: View {
    let video: FeedVideo
    let isOwn: Bool
    let options: PlaybackOptionsModel
    let download: () -> Void
    let notInterested: () -> Void
    let report: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLandscapePlayer) private var isLandscapePlayer

    // Les autres ne téléchargent que si l'auteur l'autorise ; l'auteur, toujours.
    private var canDownload: Bool { isOwn || video.downloadsEnabled }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                card {
                    row("Télécharger", systemImage: "arrow.down.to.line", identifier: "menu.download") {
                        dismiss()
                        download()
                    }
                    .disabled(!canDownload)
                    .opacity(canDownload ? 1 : 0.4)
                    if !isOwn {
                        row("Pas intéressé(e)", systemImage: "heart.slash", identifier: "menu.notInterested") {
                            dismiss()
                            notInterested()
                        }
                        row("Signaler", systemImage: "exclamationmark.triangle", identifier: "menu.report") {
                            dismiss()
                            report()
                        }
                    }
                }
                card {
                    speedRow
                    // Sans objet dans le lecteur plein écran, déjà réduit à la vidéo.
                    if !isLandscapePlayer {
                        row("Alléger l'affichage", systemImage: "viewfinder", identifier: "menu.clearMode") {
                            dismiss()
                            options.setClearMode(true)
                        }
                    }
                    autoScrollRow
                    castRow
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Self.background)
        .tint(.primary)
    }

    static let background = Color(red: 0.96, green: 0.96, blue: 0.96)

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 6)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 26)
            Text(title).font(.system(size: 17, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
    }

    private func row(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title, systemImage: systemImage)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // Vitesse : quatre segments gris, le choisi sur fond blanc.
    private var speedRow: some View {
        HStack(spacing: 10) {
            label("Vitesse", systemImage: "gauge.with.dots.needle.33percent")
            HStack(spacing: 0) {
                ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                    let selected = speed == options.speed
                    Button {
                        options.setSpeed(speed)
                    } label: {
                        Text(speed.label)
                            .font(.system(size: 14, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.black : Color(white: 0.55))
                            .frame(width: 50, height: 30)
                            .background(selected ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vitesse \(speed.label)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("menu.speed.\(speed.rawValue)")
                }
            }
            .padding(3)
            .background(Color(white: 0.93), in: RoundedRectangle(cornerRadius: 9))
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // Défilement automatique : interrupteur ; le changer ferme la feuille, le message s'affiche sur la vidéo.
    private var autoScrollRow: some View {
        HStack(spacing: 14) {
            AutoScrollIcon(color: .black).frame(width: 26)
            Text("Défilement automatique").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
            Spacer(minLength: 0)
            Toggle(
                "Défilement automatique",
                isOn: Binding(
                    get: { options.autoScroll },
                    set: { enabled in
                        dismiss()
                        options.setAutoScroll(enabled)
                    })
            )
            .labelsHidden()
            .tint(Color(red: 0.13, green: 0.82, blue: 0.85))
            .accessibilityIdentifier("menu.autoScroll")
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // Diffuser : le sélecteur AirPlay du système, posé invisible sur toute la ligne.
    private var castRow: some View {
        label("Diffuser", systemImage: "airplayvideo")
            .padding(.horizontal, 18)
            .frame(height: 54)
            .overlay { AirPlayPicker() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("menu.cast")
    }
}

// Sélecteur d'appareils AirPlay, transparent : un toucher n'importe où ouvre la liste du système.
private struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

extension EnvironmentValues {
    // Vrai dans le lecteur plein écran en paysage (et ses feuilles).
    @Entry var isLandscapePlayer = false
}
