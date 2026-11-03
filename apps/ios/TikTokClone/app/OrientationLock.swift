import UIKit

// Orientation de l'interface : l'app reste en portrait, sauf le lecteur plein écran d'une vidéo horizontale, en paysage.
// Le délégué de l'app renvoie `mask` au système ; `set` le change et fait tourner l'interface tout de suite.
@MainActor
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    // `landscape` : paysage du côté où l'iPhone est tenu (à droite par défaut).
    static func set(landscape: Bool, deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation) {
        mask = landscape ? .landscape : .portrait
        // iPhone tourné vers la gauche : interface tournée vers la droite (et inversement).
        let orientation: UIInterfaceOrientationMask =
            landscape ? (deviceOrientation == .landscapeRight ? .landscapeLeft : .landscapeRight) : .portrait
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
    {
        // Position de l'iPhone suivie pour le plein écran (iPhone tourné sur une vidéo horizontale).
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
