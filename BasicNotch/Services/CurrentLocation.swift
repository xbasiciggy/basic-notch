import CoreLocation

/// One-shot "where am I?" for the weather: asks Location Services for a fix, then names it with
/// Apple's reverse geocoder (e.g. "Long Beach, California"). Fixes are reused for 30 minutes.
@MainActor
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    struct Fix {
        let latitude: Double
        let longitude: Double
        let name: String
    }

    enum Failure: LocalizedError {
        case denied, unavailable
        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off — allow BasicNotch in System Settings › Privacy & Security › Location Services"
            case .unavailable: "Couldn't find your location right now"
            }
        }
    }

    static let shared = CurrentLocation()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation, Error>] = []
    private var lastFix: (fix: Fix, at: Date)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // city-level is plenty for weather
    }

    func fix() async throws -> Fix {
        if let last = lastFix, Date().timeIntervalSince(last.at) < 30 * 60 { return last.fix }
        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            waiters.append(continuation)
            guard waiters.count == 1 else { return }  // a request is already in flight
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()  // answered in the delegate
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: manager.requestLocation()
            }
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = [placemark?.locality ?? placemark?.name, placemark?.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        let fix = Fix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                      name: name.isEmpty ? "Current location" : name)
        lastFix = (fix, Date())
        return fix
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard !self.waiters.isEmpty else { return }
            switch status {
            case .denied, .restricted: self.finish(.failure(Failure.denied))
            case .authorizedAlways, .authorized: self.manager.requestLocation()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in self.finish(.failure(denied ? Failure.denied : Failure.unavailable)) }
    }
}
