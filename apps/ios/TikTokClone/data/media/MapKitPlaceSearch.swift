import CoreLocation
import MapKit

// Lieux d'une publication (ADR-065) : recherche Apple Plans (MapKit) et lieux autour de la position. La position ne sert
// qu'à la recherche sur l'iPhone : seuls le nom et l'adresse affichée d'un lieu choisi sont envoyés.
@MainActor
final class MapKitPlaceSearch: NSObject, PlaceSearch, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAccess, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private static let resultLimit = 20
    // Rayon des lieux à proximité.
    private static let nearbyRadius: CLLocationDistance = 2_000

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var locationAccess: LocationAccess {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        default: .denied
        }
    }

    func requestLocationAccess() async -> LocationAccess {
        guard locationAccess == .notDetermined else { return locationAccess }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func search(_ text: String) async throws -> [VideoLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        // Autour de la position quand elle est connue : des résultats proches d'abord.
        if locationAccess == .authorized, let location = manager.location {
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        return try await places(MKLocalSearch(request: request))
    }

    func nearby() async throws -> [VideoLocation] {
        guard locationAccess == .authorized, let location = await currentLocation() else { return [] }
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: Self.nearbyRadius)
        return try await places(MKLocalSearch(request: request))
    }

    private func places(_ search: MKLocalSearch) async throws -> [VideoLocation] {
        do {
            let response = try await search.start()
            var seen = Set<String>()
            return response.mapItems.compactMap(Self.location).filter { seen.insert($0.id).inserted }.prefix(Self.resultLimit).map { $0 }
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch {
            throw AppError.network
        }
    }

    // Nom du lieu et adresse lisible (numéro et rue, ville, pays), sans coordonnées.
    private static func location(_ item: MKMapItem) -> VideoLocation? {
        guard let name = item.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, placemark.locality ?? "", placemark.country ?? ""].filter { !$0.isEmpty && $0 != name }
        return VideoLocation(name: name, address: parts.isEmpty ? nil : parts.joined(separator: ", ")).bounded
    }

    private func currentLocation() async -> CLLocation? {
        if let location = manager.location, abs(location.timestamp.timeIntervalSinceNow) < 300 { return location }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.locationAccess != .notDetermined else { return }
            let access = self.locationAccess
            let waiters = self.authorizationWaiters
            self.authorizationWaiters = []
            for waiter in waiters { waiter.resume(returning: access) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.resumeLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.resumeLocation(nil) }
    }

    private func resumeLocation(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        for waiter in waiters { waiter.resume(returning: location) }
    }
}
