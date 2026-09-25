import Foundation

// Configuration lue dans Info.plist, renseigné par Config/Debug.xcconfig ou Release.xcconfig.
struct AppConfiguration: Sendable {
    let apiBaseURL: URL

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        guard let value = bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String, let url = URL(string: value) else {
            fatalError("APIBaseURL manquant ou invalide dans Info.plist : voir Config/*.xcconfig.")
        }
        return AppConfiguration(apiBaseURL: url)
    }
}
