import Combine
import CoreLocation
import MapboxDirections
import MapboxNavigationCore
import Observation

struct Guidance {
    var instruction = "Continue on the route"
    var following = ""
    var symbol = "arrow.up"
    var turnDistance: Double = 0
    var remainingTime: TimeInterval = 0
    var remainingDistance: Double = 0
    var fraction: Double = 0
    var exit: Int?
    var roundaboutAngle: Double = 0
    var lanes: [LaneGuidance] = []
    var junction: String?
    var arrival: Date { Date().addingTimeInterval(remainingTime) }
}
struct LaneGuidance: Identifiable {
    let id: Int
    let symbol: String
    let usable: Bool
}

@MainActor @Observable final class NavigationService {
    let preferences: Preferences
    private let voice: VoiceService
    private var subscriptions: Set<AnyCancellable> = []
    private var requestGeneration = 0
    private var fasterApproval: CheckedContinuation<Bool, Never>?
    var routes: NavigationRoutes?
    var active = false
    var arrived = false
    var rerouting = false
    var calculating = false
    var error: String?
    var guidance = Guidance()
    var speedLimit: Double?
    var speed: Double = 0
    var fasterRouteDescription: String?
    var startedAt: Date?
    var arrivalTime: Date?
    var traveledDistance: Double = 0
    private var previousProgressDistance: Double?
    private var previousRouteID: String?
    var onArrival: (() -> Void)?
    let mapLocations = PassthroughSubject<CLLocation, Never>()
    let mapProgress = CurrentValueSubject<RouteProgress?, Never>(nil)

    @ObservationIgnored lazy var provider: MapboxNavigationProvider = {
        var routing = RoutingConfig()
        routing.fasterRouteDetectionConfig = FasterRouteDetectionConfig(fasterRouteApproval: .manually { [weak self] context in
            guard let self else { return false }
            return await self.approveFasterRoute(duration: context.1.route.expectedTravelTime)
        })
        // Background tracking stays active for guidance; SDK stops free-drive background tracking.
        let provider = MapboxNavigationProvider(coreConfig: CoreConfig(routingConfig: routing,
            disableBackgroundTrackingLocation: true, utilizeSensorData: false,
            historyRecordingConfig: nil))
        bind(provider)
        return provider
    }()

    init(preferences: Preferences) {
        self.preferences = preferences
        voice = VoiceService(preferences: preferences)
    }
    func receive(_ location: CLLocation) {
        if !active { mapLocations.send(location); speed = max(0, location.speed) }
    }
    func beginFreeDrive() {
        guard !active else { return }
        provider.mapboxNavigation.tripSession().startFreeDrive()
    }
    func foreground(_ foreground: Bool) {
        if foreground { provider.mapboxNavigation.tripSession().restoreTrackingLocationIfNeeded() }
        else { provider.mapboxNavigation.tripSession().disableTrackingBackgroundLocationIfNeeded() }
    }
    func calculate(origin: Place, stops: [Place], destination: Place, mode: TravelMode) async {
        requestGeneration += 1
        let generation = requestGeneration
        calculating = true; error = nil
        routes = nil
        let waypoints = ([origin] + stops + [destination]).map { Waypoint(coordinate: $0.coordinate, name: $0.name) }
        let options = NavigationRouteOptions(waypoints: waypoints,
            profileIdentifier: mode == .driving ? .automobileAvoidingTraffic : .walking)
        options.includesAlternativeRoutes = stops.isEmpty
        options.locale = Locale(identifier: "en_GB")
        options.unitMeasurementSystem = preferences.units == .mph ? .imperial : .metric
        if mode == .driving {
            var exclusions: RoadClasses = []
            if preferences.avoidMotorways { exclusions.insert(.motorway) }
            if preferences.avoidTolls { exclusions.insert(.toll) }
            if preferences.avoidFerries { exclusions.insert(.ferry) }
            options.roadClassesToAvoid = exclusions
        }
        do {
            let result = try await provider.mapboxNavigation.routingProvider().calculateRoutes(options: options).value
            guard generation == requestGeneration, !Task.isCancelled else { return }
            // API's primary route is usually fastest, but explicitly compare available durations.
            if let fastest = result.alternativeRoutes.enumerated().min(by: {
                $0.element.route.expectedTravelTime < $1.element.route.expectedTravelTime
            }), fastest.element.route.expectedTravelTime < result.mainRoute.route.expectedTravelTime {
                routes = await result.selectingAlternativeRoute(at: fastest.offset) ?? result
            } else { routes = result }
        } catch {
            if generation == requestGeneration {
                self.error = "Couldn't find a route. Check your connection or change the stops, then try again."
            }
        }
        if generation == requestGeneration { calculating = false }
    }
    func select(_ alternative: AlternativeRoute) async {
        if active { provider.mapboxNavigation.navigation().selectAlternativeRoute(with: alternative.id) }
        else if let routes { self.routes = await routes.selecting(alternativeRoute: alternative) }
    }
    func start() {
        guard let routes else { return }
        arrived = false; active = true; startedAt = .now; arrivalTime = nil; traveledDistance = 0
        previousProgressDistance = nil; previousRouteID = nil
        guidance.remainingDistance = routes.mainRoute.route.distance
        guidance.remainingTime = routes.mainRoute.route.expectedTravelTime
        provider.mapboxNavigation.tripSession().startActiveGuidance(with: routes, startLegIndex: 0)
    }
    func stop() {
        resolveFasterRoute(false)
        voice.stop()
        active = false; arrived = false; rerouting = false
        mapProgress.send(nil)
        provider.mapboxNavigation.tripSession().startFreeDrive()
        routes = nil
    }
    func clearPreview() {
        requestGeneration += 1; calculating = false; routes = nil; error = nil
    }
    func voiceModeChanged() { voice.stop() }
    func resolveFasterRoute(_ accept: Bool) {
        fasterRouteDescription = nil
        let continuation = fasterApproval
        fasterApproval = nil
        continuation?.resume(returning: accept)
    }
    private func approveFasterRoute(duration: TimeInterval) async -> Bool {
        guard active, !arrived else { return false }
        resolveFasterRoute(false)
        let saved = max(1, Int((guidance.remainingTime - duration) / 60))
        fasterRouteDescription = "A faster route saves about \(saved) min. Switch routes?"
        voice.speak("A faster route is available.", alert: true)
        return await withCheckedContinuation { fasterApproval = $0 }
    }
    private func bind(_ provider: MapboxNavigationProvider) {
        let navigation = provider.mapboxNavigation.navigation()
        navigation.locationMatching.sink { [weak self] state in
            guard let self else { return }
            let limit = state.speedLimit.value?.converted(to: .metersPerSecond).value
            self.speedLimit = limit.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            self.speed = max(0, state.currentSpeed.converted(to: .metersPerSecond).value)
            self.mapLocations.send(state.enhancedLocation)
        }.store(in: &subscriptions)
        navigation.routeProgress.sink { [weak self] state in
            guard let self, self.active, let progress = state?.routeProgress else { return }
            self.mapProgress.send(progress)
            self.update(progress)
        }.store(in: &subscriptions)
        navigation.voiceInstructions.sink { [weak self] state in
            guard let self, self.active, !self.arrived else { return }
            self.voice.speak(state.spokenInstruction.text)
        }.store(in: &subscriptions)
        navigation.rerouting.sink { [weak self] status in
            guard let self else { return }
            self.rerouting = status.event is ReroutingStatus.Events.FetchingRoute
            if self.rerouting { self.voice.speak("Updating your route.", alert: true) }
            if status.event is ReroutingStatus.Events.Failed {
                self.error = "Rerouting is unavailable. Arc will keep your current route and try again."
            }
            if status.event is ReroutingStatus.Events.Fetched { self.error = nil }
        }.store(in: &subscriptions)
        navigation.waypointsArrival.sink { [weak self] status in
            guard let self, self.active, !self.arrived,
                  status.event is WaypointArrivalStatus.Events.ToFinalDestination else { return }
            self.arrived = true; self.arrivalTime = .now
            self.resolveFasterRoute(false)
            self.voice.speak("You've arrived.", alert: true)
            self.onArrival?()
        }.store(in: &subscriptions)
        provider.mapboxNavigation.tripSession().navigationRoutes.sink { [weak self] routes in
            guard let self, self.active, let routes else { return }
            self.routes = routes
        }.store(in: &subscriptions)
    }
    private func update(_ progress: RouteProgress) {
        guidance.remainingDistance = progress.distanceRemaining
        guidance.remainingTime = progress.durationRemaining
        guidance.fraction = progress.fractionTraveled
        let leg = progress.currentLegProgress
        let step = leg.upcomingStep ?? leg.currentStep
        guidance.instruction = step.instructions
        guidance.following = leg.followOnStep?.instructions ?? ""
        guidance.turnDistance = leg.currentStepProgress.distanceRemaining
        guidance.symbol = Self.symbol(step.maneuverDirection)
        guidance.exit = step.exitIndex
        guidance.roundaboutAngle = ((step.finalHeading ?? 0) - (step.initialHeading ?? 0) + 360).truncatingRemainder(dividingBy: 360)
        guidance.junction = step.exitCodes?.joined(separator: ", ")
        let intersection = leg.currentStepProgress.upcomingIntersection
        if let lanes = intersection?.approachLanes, let usable = intersection?.usableApproachLanes {
            guidance.lanes = lanes.enumerated().map { index, lane in
                let valid = intersection?.laneValidIndications
                let direction = valid.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                return LaneGuidance(id: index, symbol: direction.map { Self.symbol($0) } ?? Self.laneSymbol(lane), usable: usable.contains(index))
            }
        } else { guidance.lanes = [] }
        let routeID = String(describing: progress.routeId)
        if routeID == previousRouteID, let previous = previousProgressDistance {
            traveledDistance += max(0, progress.distanceTraveled - previous)
        }
        previousRouteID = routeID; previousProgressDistance = progress.distanceTraveled
    }
    static func symbol(_ direction: ManeuverDirection?) -> String {
        switch direction {
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .uTurn: "arrow.uturn.down"
        default: "arrow.up"
        }
    }
    private static func laneSymbol(_ lane: LaneIndication) -> String {
        if lane.contains(.left) { return "arrow.turn.up.left" }
        if lane.contains(.right) { return "arrow.turn.up.right" }
        if lane.contains(.uTurn) { return "arrow.uturn.down" }
        if lane.contains(.slightLeft) { return "arrow.up.left" }
        if lane.contains(.slightRight) { return "arrow.up.right" }
        return "arrow.up"
    }
}
