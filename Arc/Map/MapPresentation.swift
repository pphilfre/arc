import SwiftUI
import MapboxNavigationCore

/// Read observable values in SwiftUI's body so the UIKit bridge receives every map change.
@MainActor struct MapPresentation {
    let satellite: Bool
    let buildings: Bool
    let traffic: Bool
    let accent: Accent
    let active: Bool
    let mode: TravelMode
    let annotations: [ArcAnnotation]
    let routes: NavigationRoutes?
    let commandRevision: Int
    let styleRevision: Int
    init(model: ArcModel) {
        satellite = model.preferences.satellite; buildings = model.preferences.buildings
        traffic = model.preferences.traffic; accent = model.preferences.accent
        active = model.navigation.active && !model.navigation.arrived
        mode = model.mode; annotations = model.annotations; routes = model.navigation.routes
        commandRevision = model.commandRevision
        styleRevision = model.mapStyleRevision
    }
}

enum DevelopmentConfiguration {
    static var hidesMapAttribution: Bool {
        Bundle.main.object(forInfoDictionaryKey: "ArcDevelopmentMode") as? Bool == true &&
        Bundle.main.object(forInfoDictionaryKey: "ArcHideMapAttribution") as? Bool == true
    }
}
