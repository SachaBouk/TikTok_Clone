import PhotosUI
import SwiftUI
import UIKit

// Changement de la photo de profil, comme TikTok (ADR-056) : « Prendre une photo » ou « Choisir une photo »
// (« Supprimer la photo » s'il y en a une), puis le recadrage rond (`AvatarCropView`), avec « Publier cette photo en
// story » coché par défaut. Posé sur le profil (« + » de la photo) et sur « Modifier le profil » (« Changer la photo »).
extension View {
    func avatarPhotoFlow(isPresented: Binding<Bool>, viewModel: EditProfileViewModel) -> some View {
        modifier(AvatarPhotoFlow(isChoosingSource: isPresented, viewModel: viewModel))
    }
}

private struct AvatarPhotoFlow: ViewModifier {
    @Binding var isChoosingSource: Bool
    let viewModel: EditProfileViewModel
    @State private var isPickingPhoto = false
    @State private var isTakingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cropping: CroppingImage?

    struct CroppingImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Photo de profil", isPresented: $isChoosingSource, titleVisibility: .hidden) {
                // Pas de caméra dans le simulateur : l'option n'apparaît pas.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Prendre une photo") { isTakingPhoto = true }
                }
                Button("Choisir une photo") { isPickingPhoto = true }
                if viewModel.profile?.avatarURL != nil {
                    Button("Supprimer la photo", role: .destructive) { Task { await viewModel.removePhoto() } }
                }
            }
            .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        viewModel.errorMessage = "Impossible d’importer cette image."
                        return
                    }
                    cropping = CroppingImage(image: image)
                }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPhotoPicker { image in
                    isTakingPhoto = false
                    if let image { cropping = CroppingImage(image: image) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $cropping) { cropping in
                AvatarCropView(image: cropping.image, username: viewModel.profile?.username ?? "") { jpeg, postStory in
                    self.cropping = nil
                    guard let jpeg else { return }
                    Task { await viewModel.changePhoto(jpeg, postStory: postStory) }
                }
            }
    }
}

// Recadrage rond : l'image se déplace et s'agrandit au doigt (`AvatarCrop`), le reste est voilé. « Publier cette photo
// en story » (coché par défaut), « Aperçu », puis « Annuler » ou « Enregistrer et publier ».
struct AvatarCropView: View {
    let image: UIImage
    let username: String
    // JPEG carré recadré (nil : annulé) et story à publier.
    let onFinish: (Data?, Bool) -> Void
    @State private var crop: AvatarCrop?
    @State private var gestureStart: AvatarCrop?
    @State private var postStory = true
    @State private var isPreviewing = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let side = max(1, min(geometry.size.width - 32, geometry.size.height - 32))
                cropArea(side: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Le premier passage de mise en page peut donner une taille nulle : cadrage refait à la vraie taille.
                    .onChange(of: side, initial: true) { _, side in
                        if crop?.side != side { crop = AvatarCrop(imageSize: image.size, side: side) }
                    }
            }
            .navigationTitle("Recadrer")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { controls }
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $isPreviewing) {
            ProfileStoryPreview(avatar: croppedImage(), username: username, postStory: $postStory) {
                isPreviewing = false
                onFinish(croppedJPEG(), postStory)
            }
            .presentationDetents([.fraction(0.7)])
            // Fond plein (iOS 26 rend sinon la feuille translucide à cette hauteur).
            .presentationBackground(Color(.systemBackground))
        }
    }

    // « Publier cette photo en story », « Aperçu », puis « Annuler » et « Enregistrer (et publier) ».
    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    postStory.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: postStory ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(postStory ? Color.brandPink : .secondary)
                        Text("Publier cette photo en story").foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(postStory ? .isSelected : [])
                .accessibilityIdentifier("avatarCrop.postStory")
                Spacer()
                Button {
                    isPreviewing = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Aperçu")
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avatarCrop.preview")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            HStack(spacing: 12) {
                Button {
                    onFinish(nil, false)
                } label: {
                    Text("Annuler")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator)) }
                }
                .accessibilityIdentifier("avatarCrop.cancel")
                Button {
                    onFinish(croppedJPEG(), postStory)
                } label: {
                    Text(postStory ? "Enregistrer et publier" : "Enregistrer")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("avatarCrop.save")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }

    private func cropArea(side: CGFloat) -> some View {
        let current = crop.flatMap { $0.side == side ? $0 : nil } ?? AvatarCrop(imageSize: image.size, side: side)
        // L'image est en overlay : plus grande que le cadre, elle agrandirait sinon tout l'écran (piège de mise en page).
        return ZStack {
            Color.clear.overlay {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: current.displayedSize.width, height: current.displayedSize.height)
                    .offset(current.offset)
            }
            // Hors du cercle : voilé de blanc, comme TikTok.
            Rectangle()
                .fill(Color(.systemBackground).opacity(0.85))
                .mask {
                    Rectangle()
                        .overlay { Circle().frame(width: side, height: side).blendMode(.destinationOut) }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
        }
        .frame(width: side + 32, height: side + 32)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = gestureStart ?? current
                    if gestureStart == nil { gestureStart = current }
                    crop = start.with(
                        zoom: start.zoom,
                        offset: CGSize(width: start.offset.width + value.translation.width, height: start.offset.height + value.translation.height))
                }
                .onEnded { _ in gestureStart = nil }
                .simultaneously(
                    with: MagnifyGesture()
                        .onChanged { value in
                            let start = gestureStart ?? current
                            if gestureStart == nil { gestureStart = current }
                            crop = (crop ?? start).with(zoom: start.zoom * value.magnification, offset: (crop ?? start).offset)
                        }
                        .onEnded { _ in gestureStart = nil }
                )
        )
        .overlay(alignment: .bottomTrailing) {
            // Revenir au cadrage de départ.
            Button {
                withAnimation(.snappy) { crop = AvatarCrop(imageSize: image.size, side: side) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .padding(8)
            }
            .accessibilityLabel("Réinitialiser le cadrage")
            .padding(8)
        }
        .accessibilityIdentifier("avatarCrop.area")
    }

    private func croppedImage() -> UIImage? {
        guard let crop else { return nil }
        return AvatarImage.square(from: image, crop: crop.cropRect)
    }

    private func croppedJPEG() -> Data? {
        croppedImage()?.jpegData(compressionQuality: AvatarImage.quality)
    }
}

// Aperçu de la story « nouvelle photo de profil » : la carte, la case à cocher, puis « Enregistrer et publier ».
private struct ProfileStoryPreview: View {
    let avatar: UIImage?
    let username: String
    @Binding var postStory: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            if let avatar, let data = ProfilePhotoStory.render(avatar: avatar, username: username, date: .now), let card = UIImage(data: data) {
                Image(uiImage: card)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxHeight: 300)
                    .accessibilityLabel("Aperçu de la story")
            }
            Button {
                postStory.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: postStory ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(postStory ? Color.brandPink : .secondary)
                    Text("Publier cette photo en story").foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            PrimaryActionButton(title: postStory ? "Enregistrer et publier" : "Enregistrer", action: onSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// « Prendre une photo » : caméra du système (UIImagePickerController), caméra avant par défaut.
private struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onFinish: @MainActor (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraDevice = .front
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency UIImagePickerControllerDelegate, @preconcurrency UINavigationControllerDelegate {
        let onFinish: @MainActor (UIImage?) -> Void

        init(onFinish: @escaping @MainActor (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
