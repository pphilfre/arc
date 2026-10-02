import Combine
import CoreLocation
import Observation
import SwiftData

@MainActor @Observable final class ArcModel {
    let preferences = Preferences()
    let location = LocationService()
    let search = SearchService()
    let liveActivity = LiveActivityService()
    @ObservationIgnored lazy var navigation = NavigationService(preferences: preferences)
    @ObservationIgnored lazy var haptic = HapticService(preferences: preferences)
    private var locationSubscription: AnyCancellable?
    var context: ModelContext? { didSet { refreshSavedMarkers() } }
    var droppedPins: [Place] = []
    var savedMarkers: [Place] = []
    var mapStyleLoading = false
    var displayedSatellite = false
    var selectedPlace: Place?
    var destination: Place?
    var origin: Place?
    var stops: [Place] = []
    var mode: TravelMode = .driving
    var searchPurpose: SearchPurpose = .destination
    var query = ""
    var searching = false
    var showingProfile = false
    var showingLayers = false
    var planning = false
    var following = true
    var bearing: Double = 0
    var mapCommand: MapCommand = .recenter
    var commandRevision = 0
    var drivingPlaces: [Place] = []
    var notice: String?
    private var lastPOILocation: CLLocation?
    private var journeyOrigin: Place?
    private var journeyDestination: Place?
    private var journeyStops: [Place] = []
    private var journeyMode: TravelMode = .driving

    init() {
        search.onSelect = { [weak self] in self?.select($0) }
        navigation.onArrival = { [weak self] in
            guard let self, let destination = self.journeyDestination else { return }
            self.command(.focus(destination.coordinate))
            self.liveActivity.update(self.activityState)
        }
        locationSubscription = location.updates.sink { [weak self] update in
            guard let self else { return }
            self.navigation.receive(update)
            if self.preferences.drivingPOIs && !self.navigation.active {
                self.refreshDrivingPlaces(update)
            }
            if self.navigation.active || self.location.isRecording { self.liveActivity.update(self.activityState) }
        }
        if location.authorized { location.request(); navigation.beginFreeDrive() }
    }
    var currentOrigin: Place? {
        origin ?? location.location.map { Place.pin(at: $0.coordinate, name: "My Location") }
    }
    var annotations: [ArcAnnotation] {
        func group(_ places: [Place], _ role: AnnotationRole) -> [ArcAnnotation] {
            places.map { .init(place: $0, role: role) }
        }
        return ArcAnnotation.merge([
            group(savedMarkers, .saved), group(droppedPins, .dropped),
            group(preferences.drivingPOIs && !navigation.active ? drivingPlaces : [], .drivingPOI),
            group(searching ? search.places : [], search.activeCategory == nil ? .search : .category),
            group([selectedPlace].compactMap { $0 }, .selected),
            group(planning || navigation.active ? [origin, destination].compactMap { $0 } + stops : [], .destination)
        ])
    }
    func refreshSavedMarkers() {
        guard let context else { savedMarkers = []; return }
        savedMarkers = ((try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []).compactMap(\.place)
    }
    func clearSearch() { query = ""; search.clear(); selectedPlace = nil }
    func dismissSearch() { searching = false; clearSearch() }
    func dismissPlace() { selectedPlace = nil; search.clear() }
    func command(_ command: MapCommand) {
        mapCommand = command; commandRevision += 1
        switch command {
        case .recenter: following = true
        case .focus, .overview: following = false
        case .north: break
        }
    }
    func recenter() {
        haptic.tap()
        if location.authorized {
            location.request(); navigation.beginFreeDrive(); command(.recenter)
        } else if location.authorization == .notDetermined { location.request() }
        else { notice = "Enable location access for Arc in iOS Settings to recenter and use My Location." }
    }
    func openSearch(_ purpose: SearchPurpose = .destination) {
        searchPurpose = purpose
        clearSearch()
        searching = true; haptic.tap()
    }
    func select(_ place: Place) {
        haptic.tap()
        recordSearch(query.isEmpty ? place.name : query)
        searching = false
        search.clear()
        selectedPlace = nil
        switch searchPurpose {
        case .origin: origin = place; Task { await calculate() }
        case .stop: stops.append(place); Task { await calculate() }
        case .destination:
            selectedPlace = place
            search.enrich(place) { [weak self] enriched in
                guard self?.selectedPlace?.id == place.id else { return }
                self?.selectedPlace = enriched
            }
        }
        command(.focus(place.coordinate))
    }
    func dropPin(_ coordinate: CLLocationCoordinate2D, name: String? = nil) {
        search.clear()
        let pin = Place.pin(at: coordinate, name: name ?? "Dropped pin")
        droppedPins.append(pin)
        selectedPlace = pin
        if let name, let pinID = selectedPlace?.id {
            search.mapPlace(named: name, near: coordinate) { [weak self] result in
                guard let self, let result, self.selectedPlace?.id == pinID else { return }
                self.droppedPins.removeAll { $0.id == pinID }
                self.selectedPlace = result
                self.search.enrich(result) { [weak self] enriched in
                    guard self?.selectedPlace?.id == result.id else { return }
                    self?.selectedPlace = enriched
                }
            }
        }
        haptic.tap()
    }
    func directions(to place: Place) {
        destination = place; selectedPlace = nil; search.clear(); planning = true
        if currentOrigin == nil { location.request() }
        Task { await calculate() }
    }
    func calculate() async {
        guard let destination else { return }
        guard let origin = currentOrigin else {
            notice = "Choose a starting place or enable location access to find directions."
            return
        }
        await navigation.calculate(origin: origin, stops: stops, destination: destination, mode: mode)
        if navigation.routes != nil { command(.overview) }
    }
    func cancelPlanning() {
        navigation.clearPreview(); planning = false; destination = nil; origin = nil; stops = []
        command(.recenter)
    }
    func startNavigation() {
        guard let currentOrigin, let destination, navigation.routes != nil else { return }
        if !location.authorized { location.request(); notice = "Location access is required to start navigation."; return }
        if location.location?.horizontalAccuracy ?? 999 > 100 {
            notice = "Waiting for an accurate location. Try again when Arc has a GPS fix."; return
        }
        if let fix = location.location, fix.distance(from: currentOrigin.location) > 200 {
            notice = "You're away from this starting point. Use My Location before starting guidance."; return
        }
        if location.isRecording { location.stopMovement(); liveActivity.end() }
        journeyOrigin = currentOrigin; journeyDestination = destination
        journeyStops = stops; journeyMode = mode
        location.setJourneyActive(true)
        navigation.start(); planning = false; searching = false; selectedPlace = nil
        haptic.tap(); command(.recenter)
        liveActivity.start(destination: destination.name, navigation: true, state: activityState)
    }
    /// The session stays active through arrival until the user chooses Finish.
    func finishNavigation() {
        if navigation.arrived, let start = journeyOrigin, let destination = journeyDestination, let context {
            do {
                let journey = try Journey(start: start, destination: destination, stops: journeyStops,
                    distance: navigation.traveledDistance,
                    duration: (navigation.arrivalTime ?? .now).timeIntervalSince(navigation.startedAt ?? .now),
                    arrival: navigation.arrivalTime ?? .now, mode: journeyMode)
                context.insert(journey); try context.save()
            } catch { notice = "This journey couldn't be saved. Your saved places are still available." }
        }
        navigation.stop(); location.setJourneyActive(false); liveActivity.end()
        destination = nil; origin = nil; stops = []; journeyOrigin = nil; journeyDestination = nil
        haptic.tap(); command(.recenter)
    }
    func toggleMovement() {
        if location.isRecording { location.stopMovement(); liveActivity.end() }
        else if location.authorized {
            location.startMovement(); navigation.beginFreeDrive()
            liveActivity.start(destination: "Movement", navigation: false, state: activityState)
        } else { location.request() }
        haptic.tap()
    }
    func recordSearch(_ text: String) {
        guard let context else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            var all = try context.fetch(FetchDescriptor<RecentSearch>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            if let existing = all.first(where: { $0.query.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                existing.date = .now
            } else {
                let recent = RecentSearch(query: value)
                context.insert(recent); all.append(recent)
            }
            for stale in all.sorted(by: { $0.date > $1.date }).dropFirst(20) { context.delete(stale) }
            try context.save()
        } catch { notice = "Recent searches couldn't be saved." }
    }
    func toggleSave(_ place: Place) {
        guard let context else { return }
        do {
            let saved = try context.fetch(FetchDescriptor<SavedPlace>())
            if let existing = saved.first(where: { $0.placeID == place.id }) { context.delete(existing) }
            else { context.insert(try SavedPlace(place: place)) }
            try context.save(); refreshSavedMarkers(); haptic.tap(success: true)
        } catch { notice = "This place couldn't be saved. Try again." }
    }
    func refreshDrivingPlaces(_ update: CLLocation? = nil) {
        guard preferences.drivingPOIs, let fix = update ?? location.location else { return }
        if let lastPOILocation, fix.distance(from: lastPOILocation) < 1500 { return }
        lastPOILocation = fix
        search.drivingPlaces(proximity: fix.coordinate) { [weak self] in self?.drivingPlaces = $0 }
    }
    var activityState: ArcActivityAttributes.ContentState {
        let guidance = navigation.guidance
        let units = preferences.units
        return .init(instruction: navigation.arrived ? "You've arrived" : guidance.instruction,
            symbol: navigation.arrived ? "checkmark" : guidance.symbol,
            distanceToTurn: units.distance(guidance.turnDistance),
            remainingDistance: units.distance(guidance.remainingDistance), arrival: guidance.arrival,
            currentSpeed: units.speed(navigation.speed), averageSpeed: units.speed(location.session.averageSpeed),
            units: units.rawValue, sessionDistance: units.distance(location.session.distance),
            startedAt: navigation.active ? navigation.startedAt ?? .now : location.session.startedAt,
            arrived: navigation.arrived)
    }
}
