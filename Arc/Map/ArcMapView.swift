import SwiftUI
import MapboxMaps
import MapboxNavigationCore
import MapboxDirections
import Combine
import CoreLocation
import UIKit

struct ArcMapView: UIViewRepresentable {
    let model: ArcModel
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> NavigationMapView {
        let navigation = model.navigation.provider.mapboxNavigation.navigation()
        let view = NavigationMapView(location: model.navigation.mapLocations.eraseToAnyPublisher(),
            routeProgress: model.navigation.mapProgress.eraseToAnyPublisher(),
            routeRefreshing: navigation.routeRefreshing,
            heading: navigation.heading,
            predictiveCacheManager: model.navigation.provider.predictiveCacheManager)
        view.delegate = context.coordinator
        view.navigationCamera.stop()
        view.mapView.mapboxMap.setCamera(to: CameraOptions(
            center: model.location.location?.coordinate ?? .init(latitude: 51.5074, longitude: -0.1278),
            zoom: 15, bearing: 0, pitch: 0))
        view.puckType = .puck2D(Puck2DConfiguration(topImage: Self.arrowImage(), bearingImage: nil, shadowImage: nil))
        view.puckBearing = .heading
        view.mapView.ornaments.options.compass.visibility = .hidden
        view.mapView.ornaments.options.logo.position = .topLeft
        view.mapView.ornaments.options.logo.margins = CGPoint(x: 12, y: 62)
        view.mapView.ornaments.options.attributionButton.position = .topRight
        view.mapView.ornaments.options.attributionButton.margins = CGPoint(x: 12, y: 62)
        view.routeAlternateColor = .systemGray
        view.routeAlternateCasingColor = .systemGray2
        view.showsRelativeDurationsOnAlternativeManuever = false
        view.viewportPadding = UIEdgeInsets(top: 200, left: 36, bottom: 300, right: 36)
        context.coordinator.attach(view)
        return view
    }
    func updateUIView(_ view: NavigationMapView, context: Context) {
        context.coordinator.update(view, scheme: colorScheme)
    }
    static func dismantleUIView(_ view: NavigationMapView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.cancelables.removeAll()
    }
    private static func arrowImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 38, height: 44)).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 19, y: 3)); path.addLine(to: CGPoint(x: 33, y: 37))
            path.addLine(to: CGPoint(x: 19, y: 29)); path.addLine(to: CGPoint(x: 5, y: 37)); path.close()
            UIColor.systemBlue.setFill(); path.fill()
            UIColor.white.setStroke(); path.lineWidth = 2.5; path.stroke()
        }
    }

    @MainActor final class Coordinator: NSObject, NavigationMapViewDelegate {
        let model: ArcModel
        weak var view: NavigationMapView?
        var cancelables: Set<AnyCancelable> = []
        private var locationSubscription: AnyCancellable?
        private var annotations: PointAnnotationManager?
        private var previousMarkers: [Place] = []
        private var previousRoutes: NavigationRoutes?
        private var styleKey = ""
        private var paletteKey = ""
        private var flattened = false
        private var lastCommand = -1
        private var wasActive = false
        private var firstLocation = true
        private var stableSpeed: Double = 0
        private var speedChangedAt = Date()
        private var targetSpeed: Double = 0
        private var lastZoomUpdate = Date.distantPast
        private var lastBearingUpdate = Date.distantPast

        init(model: ArcModel) { self.model = model }
        func attach(_ view: NavigationMapView) {
            self.view = view
            annotations = view.mapView.annotations.makePointAnnotationManager(id: "arc-places")
            view.mapView.mapboxMap.onCameraChanged.observe { [weak self] event in
                guard let self else { return }
                if abs(self.model.bearing - event.cameraState.bearing) > 0.5,
                   Date().timeIntervalSince(self.lastBearingUpdate) > 0.1 {
                    self.lastBearingUpdate = .now
                    self.model.bearing = event.cameraState.bearing
                }
                // Standard's 3D buildings flatten naturally as the zoom falls; pitch follows browsing zoom.
                if !self.model.navigation.active, self.model.preferences.buildings {
                    let desired = event.cameraState.zoom < 13 ? 0.0 : 45.0
                    if self.flattened != (desired == 0) {
                        self.flattened = desired == 0
                        view.mapView.camera.ease(to: CameraOptions(pitch: desired), duration: 0.7)
                    }
                }
            }.store(in: &cancelables)
            view.mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
                self?.installTraffic()
            }.store(in: &cancelables)
            locationSubscription = model.navigation.mapLocations.sink { [weak self] location in
                self?.locationChanged(location)
            }
        }
        func update(_ view: NavigationMapView, scheme: ColorScheme) {
            let preferences = model.preferences
            let active = model.navigation.active && !model.navigation.arrived
            let key = "\(preferences.satellite)-\(preferences.buildings)-\(preferences.traffic)-\(scheme)-\(active)"
            if key != styleKey {
                styleKey = key
                if preferences.satellite {
                    view.mapView.mapboxMap.mapStyle = .standardSatellite(lightPreset: scheme == .dark ? .night : .day,
                        showPointOfInterestLabels: !active)
                } else {
                    view.mapView.mapboxMap.mapStyle = .standard(lightPreset: scheme == .dark ? .night : .day,
                        showPointOfInterestLabels: !active, showTransitLabels: !active,
                        show3dObjects: preferences.buildings || active)
                }
                installTraffic()
            }
            let palette = "\(preferences.accent)-\(preferences.traffic)"
            if palette != paletteKey {
                paletteKey = palette
                view.routeColor = UIColor(preferences.accent.color)
                view.routeCasingColor = UIColor(preferences.accent.color).withAlphaComponent(0.65)
                view.showsTrafficOnRouteLine = preferences.traffic
                var congestion = view.congestionConfiguration
                congestion.colors.alternativeRouteColors.low = .systemGray
                congestion.colors.alternativeRouteColors.moderate = .systemGray
                congestion.colors.alternativeRouteColors.heavy = .systemGray
                congestion.colors.alternativeRouteColors.severe = .systemGray
                congestion.colors.alternativeRouteColors.unknown = .systemGray
                view.congestionConfiguration = congestion
            }
            if let source = view.navigationCamera.viewportDataSource as? MobileViewportDataSource {
                source.options.followingCameraOptions.defaultPitch = active && model.mode == .driving ? 55 : 0
                source.options.followingCameraOptions.pitchNearManeuver.triggerDistanceToManeuver = 200
                source.options.followingCameraOptions.geometryFramingAfterManeuver.distanceToCoalesceCompoundManeuvers = 160
                source.options.followingCameraOptions.zoomUpdatesAllowed = !active
            }
            if model.navigation.routes != previousRoutes {
                previousRoutes = model.navigation.routes
                if let routes = previousRoutes {
                    if model.navigation.active { view.show(routes, routeAnnotationKinds: [.relativeDurationsOnAlternative]) }
                    else { view.showcase(routes, routeAnnotationKinds: [.routeDurations], animated: true) }
                } else { view.removeRoutes() }
            }
            let markers = model.markers
            if markers != previousMarkers {
                previousMarkers = markers
                annotations?.annotations = markers.map { place in
                    var point = PointAnnotation(id: place.id, coordinate: place.coordinate)
                    point.image = .init(image: Self.pinImage(color: UIColor(preferences.accent.color)), name: "arc-pin-\(preferences.accent.rawValue)")
                    point.iconAnchor = .bottom
                    point.textField = place.name
                    point.textOffset = [0, 1.1]
                    point.textSize = 12
                    point.textHaloColor = StyleColor(.systemBackground)
                    point.textHaloWidth = 2
                    return point.onTapGesture { [weak self] in
                        self?.model.searchPurpose = .destination
                        self?.model.select(place)
                    }
                }
            }
            if active != wasActive {
                wasActive = active
                view.puckBearing = active ? .course : .heading
                view.mapView.ornaments.options.logo.position = active ? .bottomLeft : .topLeft
                view.mapView.ornaments.options.attributionButton.position = active ? .bottomRight : .topRight
                view.mapView.ornaments.options.logo.margins = CGPoint(x: 12, y: active ? 160 : 62)
                view.mapView.ornaments.options.attributionButton.margins = CGPoint(x: 12, y: active ? 160 : 62)
                if !active { view.navigationCamera.stop() }
            }
            if lastCommand != model.commandRevision {
                lastCommand = model.commandRevision
                switch model.mapCommand {
                case .recenter:
                    if active { view.navigationCamera.update(cameraState: .following) }
                    else if let location = model.location.location {
                        view.navigationCamera.stop()
                        view.mapView.camera.ease(to: CameraOptions(center: location.coordinate, zoom: 15,
                            bearing: 0, pitch: preferences.buildings ? 45 : 0), duration: 0.9)
                    }
                case .north:
                    view.mapView.camera.ease(to: CameraOptions(bearing: 0), duration: 0.6)
                case .overview:
                    if active { view.navigationCamera.update(cameraState: .overview) }
                    else if let routes = model.navigation.routes {
                        view.navigationCamera.stop()
                        view.showcase(routes, routeAnnotationKinds: [.routeDurations], animated: true)
                    }
                case .focus(let coordinate):
                    view.navigationCamera.stop()
                    view.mapView.camera.ease(to: CameraOptions(center: coordinate, zoom: 16.5, bearing: 0,
                        pitch: preferences.buildings ? 45 : 0), duration: 1.1)
                }
            }
        }
        private func locationChanged(_ location: CLLocation) {
            guard let view else { return }
            if !model.navigation.active && model.following {
                view.mapView.camera.ease(to: CameraOptions(center: location.coordinate,
                    zoom: firstLocation ? 15 : nil), duration: firstLocation ? 0.9 : 0.8)
                firstLocation = false
            }
            guard model.navigation.active, !model.navigation.arrived, model.following,
                  let source = view.navigationCamera.viewportDataSource as? MobileViewportDataSource else { return }
            let speed = max(0, location.speed)
            if abs(speed - targetSpeed) > 4 { targetSpeed = speed; speedChangedAt = .now }
            if Date().timeIntervalSince(speedChangedAt) > 3 { stableSpeed += (targetSpeed - stableSpeed) * 0.12 }
            guard Date().timeIntervalSince(lastZoomUpdate) > 1 else { return }
            lastZoomUpdate = .now
            let complex = !model.navigation.guidance.lanes.isEmpty || model.navigation.guidance.exit != nil
            let nearTurn = model.navigation.guidance.turnDistance < (complex ? 300 : 160)
            let zoom = model.mode == .walking ? 17.4 : (nearTurn ? 17.4 : max(14.8, 17.2 - stableSpeed / 22))
            let current = Double(source.currentNavigationCameraOptions.followingCamera.zoom ?? 16)
            source.currentNavigationCameraOptions.followingCamera.zoom = CGFloat(current + (zoom - current) * 0.22)
        }
        private func installTraffic() {
            guard let map = view?.mapView.mapboxMap, map.isStyleLoaded else { return }
            if map.layerExists(withId: "arc-traffic") { try? map.removeLayer(withId: "arc-traffic") }
            if map.sourceExists(withId: "arc-traffic-source") { try? map.removeSource(withId: "arc-traffic-source") }
            guard model.preferences.traffic else { return }
            var source = VectorSource(id: "arc-traffic-source")
            source.url = "mapbox://mapbox.mapbox-traffic-v1"
            var layer = LineLayer(id: "arc-traffic", source: source.id)
            layer.sourceLayer = "traffic"
            layer.slot = "middle"
            layer.minZoom = 8
            layer.lineWidth = .constant(2.5)
            layer.lineOpacity = .constant(0.72)
            layer.lineColor = .expression(Exp(.match) {
                Exp(.get) { "congestion" }
                "low"; "#45B87C"
                "moderate"; "#E8A83C"
                "heavy"; "#EB6548"
                "severe"; "#B72C40"
                "rgba(0,0,0,0)"
            })
            do { try map.addSource(source); try map.addLayer(layer) }
            catch { model.notice = "Traffic couldn't load. The map and directions are still available." }
        }
        func navigationMapView(_ navigationMapView: NavigationMapView, didSelect alternativeRoute: AlternativeRoute) {
            model.haptic.tap()
            Task { await model.navigation.select(alternativeRoute) }
        }
        func navigationMapView(_ navigationMapView: NavigationMapView, userDidTap mapPoint: MapPoint) {
            guard !model.navigation.active else { return }
            model.dropPin(mapPoint.coordinate, name: mapPoint.name)
        }
        func navigationMapView(_ navigationMapView: NavigationMapView, userDidLongTap mapPoint: MapPoint) {
            guard !model.navigation.active else { return }
            model.dropPin(mapPoint.coordinate)
        }
        func navigationMapViewUserDidStartInteraction(_ navigationMapView: NavigationMapView) {
            model.following = false
            navigationMapView.navigationCamera.stop()
        }
        private static func pinImage(color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 32, height: 42)).image { _ in
                let path = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 28, height: 28))
                color.setFill(); path.fill()
                let tip = UIBezierPath(); tip.move(to: CGPoint(x: 7, y: 24)); tip.addLine(to: CGPoint(x: 16, y: 41))
                tip.addLine(to: CGPoint(x: 25, y: 24)); tip.close(); tip.fill()
                UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 11, y: 11, width: 10, height: 10)).fill()
            }
        }
    }
}
