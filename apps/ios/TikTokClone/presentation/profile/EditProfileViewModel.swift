import Foundation
import Observation
import UIKit

// Modification de son profil : nom, pseudo, bio (chacun sur sa page, seuls les champs changés sont envoyés), et photo
// (recadrée en rond puis appliquée tout de suite ; story « nouvelle photo de profil » si elle est cochée, ADR-056).
// `notice` : message bref affiché après un enregistrement (« Enregistré »).
@MainActor
@Observable
final class EditProfileViewModel {
    var displayName: String
    var username: String
    var bio: String
    var errorMessage: String?
    var notice: String?
    private(set) var isSaving = false
    private(set) var isChangingPhoto = false

    private let updateProfile: UpdateProfileUseCase
    private let changeAvatar: ChangeAvatarUseCase
    private let removeAvatar: RemoveAvatarUseCase
    private let session: SessionStore
    private let prepareImage: @Sendable (Data) -> Data?
    // Publie la story « nouvelle photo de profil » à partir de la photo recadrée ; renvoie un message d'erreur.
    private let publishStory: (@MainActor (Data) async -> String?)?

    init(
        updateProfile: UpdateProfileUseCase,
        changeAvatar: ChangeAvatarUseCase,
        removeAvatar: RemoveAvatarUseCase,
        session: SessionStore,
        prepareImage: @escaping @Sendable (Data) -> Data? = { AvatarImage.jpeg(from: $0) },
        publishStory: (@MainActor (Data) async -> String?)? = nil
    ) {
        self.updateProfile = updateProfile
        self.changeAvatar = changeAvatar
        self.removeAvatar = removeAvatar
        self.session = session
        self.prepareImage = prepareImage
        self.publishStory = publishStory
        displayName = session.profile?.displayName ?? ""
        username = session.profile?.username ?? ""
        bio = session.profile?.bio ?? ""
    }

    var profile: UserProfile? { session.profile }

    var remainingBioCharacters: Int {
        ProfileRules.maxBioLength - bio.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    // Quelque chose à enregistrer (les champs invalides le sont aussi : le message s'affiche à l'envoi).
    var hasChanges: Bool {
        guard let profile else { return false }
        switch ProfileRules.changes(from: profile, username: username, displayName: displayName, bio: bio) {
        case .success(let changes): return !changes.isEmpty
        case .failure: return true
        }
    }

    // Champs remis à l'état du profil (« Annuler » d'une page de modification).
    func reset() {
        displayName = session.profile?.displayName ?? ""
        username = session.profile?.username ?? ""
        bio = session.profile?.bio ?? ""
    }

    // Vrai si le profil est enregistré (la page peut se fermer).
    func save() async -> Bool {
        guard let profile, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            session.update(try await updateProfile(profile, username: username, displayName: displayName, bio: bio))
            notice = "Enregistré"
            return true
        } catch {
            errorMessage = handle(error)
            return false
        }
    }

    // `data` : la photo recadrée (ou une image de la galerie, recadrée au centre) ; ramenée à un carré de 512 px en
    // JPEG. `postStory` : la story « nouvelle photo de profil » part ensuite dans la file d'envoi, si la photo est enregistrée.
    func changePhoto(_ data: Data, postStory: Bool = false) async {
        guard !isChangingPhoto else { return }
        guard let jpeg = prepareImage(data) else {
            errorMessage = "Cette image n’a pas pu être lue."
            return
        }
        isChangingPhoto = true
        defer { isChangingPhoto = false }
        do {
            session.update(try await changeAvatar(jpeg, type: .jpeg))
            notice = "Enregistré"
        } catch {
            errorMessage = handle(error)
            return
        }
        guard postStory, let publishStory else { return }
        if let message = await publishStory(jpeg) {
            errorMessage = message
        } else {
            notice = "Ta story est en cours de publication. Tout le monde pourra la voir."
        }
    }

    func removePhoto() async {
        guard !isChangingPhoto else { return }
        isChangingPhoto = true
        defer { isChangingPhoto = false }
        do {
            session.update(try await removeAvatar())
        } catch {
            errorMessage = handle(error)
        }
    }

    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        return error.message
    }
}

// Photo de profil (choix du développeur : pas de traitement côté serveur) : recadrage carré au centre,
// 512 px de côté, JPEG. L'orientation de la photo est appliquée.
enum AvatarImage {
    static let quality: CGFloat = 0.85

    // Carré `crop` (en points de l'image, orientation appliquée) dessiné sur 512 px (recadrage rond, `AvatarCrop`).
    static func square(from image: UIImage, crop: CGRect) -> UIImage? {
        guard crop.width > 0 else { return nil }
        let side = CGFloat(ProfileRules.avatarSide)
        let ratio = side / crop.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(
                in: CGRect(x: -crop.minX * ratio, y: -crop.minY * ratio, width: image.size.width * ratio, height: image.size.height * ratio))
        }
    }

    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let side = CGFloat(ProfileRules.avatarSide)
        let scale = side / min(image.size.width, image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        return square.jpegData(compressionQuality: quality)
    }
}
