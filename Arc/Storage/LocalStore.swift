import SwiftData
import Foundation

@Model final class SavedPlace {
    @Attribute(.unique) var placeID: String
    var data: Data
    var savedAt: Date
    init(place: Place) throws {
        placeID = place.id
        data = try JSONEncoder().encode(place)
        savedAt = .now
    }
    var place: Place? { try? JSONDecoder().decode(Place.self, from: data) }
}

@Model final class RecentSearch {
    @Attribute(.unique) var query: String
    var date: Date
    init(query: String) { self.query = query; date = .now }
}

@Model final class Journey {
    var id: UUID
    var start: Data
    var destination: Data
    var stops: Data
    var distance: Double
    var duration: TimeInterval
    var arrival: Date
    var mode: String
    init(start: Place, destination: Place, stops: [Place], distance: Double,
         duration: TimeInterval, arrival: Date, mode: TravelMode) throws {
        id = UUID()
        let encoder = JSONEncoder()
        self.start = try encoder.encode(start)
        self.destination = try encoder.encode(destination)
        self.stops = try encoder.encode(stops)
        self.distance = distance
        self.duration = duration
        self.arrival = arrival
        self.mode = mode.rawValue
    }
    var destinationPlace: Place? { try? JSONDecoder().decode(Place.self, from: destination) }
    var startPlace: Place? { try? JSONDecoder().decode(Place.self, from: start) }
    var stopPlaces: [Place] { (try? JSONDecoder().decode([Place].self, from: stops)) ?? [] }
}

