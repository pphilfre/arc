import CoreLocation
import Foundation

struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String = ""
    var category: String = "Place"
    var phone: String?
    var website: URL?
    var imageURL: URL?
    var openingInformation: String?
    var openingSchedule: OpeningSchedule?
    var mapboxID: String?

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
    var shareText: String {
        var url = URLComponents(string: "https://maps.apple.com/")!
        url.queryItems = [.init(name: "ll", value: "\(latitude),\(longitude)"), .init(name: "q", value: name)]
        return "\(name)\n\(address)\n\(url.url!.absoluteString)"
    }
    static func pin(at coordinate: CLLocationCoordinate2D, name: String = "Dropped pin") -> Place {
        .init(id: UUID().uuidString, name: name, latitude: coordinate.latitude,
              longitude: coordinate.longitude,
              address: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
    }
}

enum TravelMode: String, CaseIterable, Identifiable {
    case driving = "Driving", walking = "Walking"
    var id: String { rawValue }
    var symbol: String { self == .driving ? "car.fill" : "figure.walk" }
}

enum SearchPurpose { case destination, origin, stop }
enum MapCommand {
    case recenter, north, overview
    case focus(CLLocationCoordinate2D)
}
