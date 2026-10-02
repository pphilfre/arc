import CoreLocation
import Combine
import Observation

@MainActor @Observable final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    let updates = PassthroughSubject<CLLocation, Never>()
    var location: CLLocation?
    var authorization: CLAuthorizationStatus = .notDetermined
    var error: String?
    var session = MovementSession()
    var isRecording = false
    private var backgroundJourney = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
        manager.activityType = .otherNavigation
        authorization = manager.authorizationStatus
    }
    var authorized: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }
    func request() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if authorized { manager.startUpdatingLocation() }
    }
    func startMovement() {
        request()
        session = MovementSession()
        isRecording = true
        setJourneyActive(true)
    }
    func stopMovement() { isRecording = false; setJourneyActive(false) }
    func setJourneyActive(_ active: Bool) {
        backgroundJourney = active
        manager.activityType = active ? .automotiveNavigation : .otherNavigation
        manager.desiredAccuracy = active ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = active ? 2 : 5
        manager.allowsBackgroundLocationUpdates = active && authorized
        manager.showsBackgroundLocationIndicator = active
        if active && authorization == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }
    func foreground(_ active: Bool) {
        if active && authorized { manager.startUpdatingLocation() }
        else if !backgroundJourney { manager.stopUpdatingLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorized { manager.startUpdatingLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy < 100, abs(latest.timestamp.timeIntervalSinceNow) < 15 else { return }
        location = latest
        error = nil
        if isRecording { session.record(latest) }
        updates.send(latest)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = "Location is unavailable. Check Location Services and try recentering."
    }
}

/// Keeps aggregate statistics and one previous sample in memory; never persists a trace.
struct MovementSession {
    let startedAt = Date()
    private(set) var distance: Double = 0
    private var previous: CLLocation?
    var duration: TimeInterval { Date().timeIntervalSince(startedAt) }
    var averageSpeed: Double { duration > 0 ? distance / duration : 0 }
    mutating func record(_ location: CLLocation) {
        defer { previous = location }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40,
              let previous, previous.horizontalAccuracy <= 40 else { return }
        let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
        let delta = location.distance(from: previous)
        // Reject stale samples, GPS jitter at rest, and impossible jumps.
        guard elapsed > 0, elapsed < 30, delta / elapsed < 85,
              location.speed > 0.8, delta > max(2, location.horizontalAccuracy * 0.25) else { return }
        distance += delta
    }
}

