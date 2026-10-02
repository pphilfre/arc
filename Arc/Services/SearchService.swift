import CoreLocation
import MapboxSearch
import Observation

struct SearchRow: Identifiable {
    let suggestion: any SearchSuggestion
    var id: String { suggestion.id }
    var name: String { suggestion.name }
    var detail: String { suggestion.descriptionText ?? "" }
}
struct SearchCategory: Identifiable {
    let name: String
    let symbol: String
    let key: String
    var id: String { key }
    static let all: [Self] = [
        .init(name: "Food", symbol: "fork.knife", key: "restaurant"),
        .init(name: "Petrol", symbol: "fuelpump.fill", key: "gas_station"),
        .init(name: "Parking", symbol: "parkingsign", key: "parking_lot"),
        .init(name: "Coffee", symbol: "cup.and.saucer.fill", key: "cafe"),
        .init(name: "Groceries", symbol: "basket.fill", key: "grocery"),
        .init(name: "EV Charging", symbol: "bolt.car.fill", key: "ev_charging_station"),
        .init(name: "Hotels", symbol: "bed.double.fill", key: "hotel")
    ]
}

@MainActor @Observable final class SearchService: NSObject, SearchEngineDelegate {
    private let engine = SearchEngine(locationProvider: nil, apiType: .searchBox)
    private let categoryEngine = CategorySearchEngine(locationProvider: nil, apiType: .searchBox)
    var rows: [SearchRow] = []
    var places: [Place] = []
    var busy = false
    var error: String?
    var onSelect: ((Place) -> Void)?
    private var selecting = false
    private var generation = 0
    private var detailRequests: [UUID: PlaceDetailsRequest] = [:]

    override init() { super.init(); engine.delegate = self }
    func search(_ query: String, proximity: CLLocationCoordinate2D?) {
        generation += 1
        selecting = false
        error = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rows = []; places = []; busy = false; return
        }
        busy = true
        places = []
        engine.search(query: query, options: SearchOptions(proximity: proximity))
    }
    func select(_ row: SearchRow) {
        selecting = true
        busy = true
        engine.select(suggestion: row.suggestion, options: RetrieveOptions(attributeSets: [.basic, .photos, .visit]))
    }
    func submit(_ query: String, proximity: CLLocationCoordinate2D?) {
        generation += 1
        let current = generation
        busy = true; rows = []; places = []; error = nil
        engine.forward(query: query, options: SearchOptions(proximity: proximity)) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.busy = false
                switch result {
                case .success(let results): self.places = results.map(Self.place)
                case .failure: self.error = "Search is unavailable. Check your connection and try again."
                }
            }
        }
    }
    func category(_ category: SearchCategory, proximity: CLLocationCoordinate2D?) {
        generation += 1
        let current = generation
        rows = []; places = []; busy = true; error = nil
        categoryEngine.search(categoryName: category.key, options: SearchOptions(proximity: proximity)) { [weak self] result in
            guard let self, self.generation == current else { return }
            self.busy = false
            switch result {
            case .success(let results): self.places = results.map(Self.place)
            case .failure: self.error = "Search is unavailable. Check your connection and try again."
            }
        }
    }
    func drivingPlaces(proximity: CLLocationCoordinate2D, completion: @escaping ([Place]) -> Void) {
        // Keep these results independent of the user's current search sheet.
        let nearbyEngine = CategorySearchEngine(locationProvider: nil, apiType: .searchBox)
        nearbyEngine.search(categoryNames: ["gas_station", "ev_charging_station", "parking_lot"],
            options: SearchOptions(proximity: proximity)) { [nearbyEngine] result in
                _ = nearbyEngine
                let stations = (try? result.get().map(Self.place)) ?? []
                // Services are a free-text search, avoiding an unsupported category identifier.
                let services = SearchEngine(locationProvider: nil, apiType: .searchBox)
                services.forward(query: "motorway services", options: SearchOptions(proximity: proximity)) { [services] result in
                    _ = services
                    Task { @MainActor in
                        let center = CLLocation(latitude: proximity.latitude, longitude: proximity.longitude)
                        let restStops = ((try? result.get()) ?? []).map(Self.place).filter { $0.location.distance(from: center) < 5000 }
                        completion(stations + restStops)
                    }
                }
            }
    }
    func enrich(_ place: Place, completion: @escaping (Place) -> Void) {
        guard let mapboxID = place.mapboxID else { completion(place); return }
        let id = UUID()
        let request = PlaceDetailsRequest { [weak self] result in
            self?.detailRequests[id] = nil
            completion(result.map(Self.place) ?? place)
        }
        detailRequests[id] = request
        request.start(mapboxID)
    }
    func mapPlace(named name: String, near coordinate: CLLocationCoordinate2D, completion: @escaping (Place?) -> Void) {
        let nearby = SearchEngine(locationProvider: nil, apiType: .searchBox)
        nearby.forward(query: name, options: SearchOptions(proximity: coordinate)) { [nearby] result in
            _ = nearby
            Task { @MainActor in
                let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let matches = ((try? result.get()) ?? []).map(Self.place).filter {
                    $0.location.distance(from: point) < 150 && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }
                completion(matches.min { $0.location.distance(from: point) < $1.location.distance(from: point) })
            }
        }
    }
    func suggestionsUpdated(suggestions: [any SearchSuggestion], searchEngine: SearchEngine) {
        rows = suggestions.map { SearchRow(suggestion: $0) }
        busy = false
        // Search Box suggestions resolve on selection. Submit uses forward search for map markers.
    }
    func resultResolved(result: any SearchResult, searchEngine: SearchEngine) {
        busy = false
        let place = Self.place(result)
        places = [place]
        if selecting { selecting = false; onSelect?(place) }
    }
    func resultsResolved(results: [any SearchResult], searchEngine: SearchEngine) {
        if !selecting { places = results.map(Self.place); busy = false }
    }
    func searchErrorHappened(searchError: SearchError, searchEngine: SearchEngine) {
        busy = false
        error = "Search is unavailable. Check your connection and try again."
    }
    static func place(_ result: any SearchResult) -> Place {
        let metadata = result.metadata
        var hours: String?
        if let openHours = metadata?.openHours {
            switch openHours {
            case .alwaysOpened: hours = "Open 24 hours"
            case .temporarilyClosed: hours = "Temporarily closed"
            case .permanentlyClosed: hours = "Permanently closed"
            case .scheduled(_, let weekdayText, let note):
                hours = note ?? weekdayText?.joined(separator: "\n")
            }
        }
        return Place(id: result.mapboxId ?? result.id, name: result.name,
            latitude: result.coordinate.latitude, longitude: result.coordinate.longitude,
            address: result.address?.formattedAddress(style: .medium) ?? result.descriptionText ?? "",
            category: result.categories?.first ?? "Place", phone: metadata?.phone,
            website: metadata?.website, imageURL: metadata?.primaryImage?.sizes.first?.url,
            openingInformation: hours, mapboxID: result.mapboxId)
    }
}

/// Each detail lookup has its own engine, so it cannot disturb an autocomplete session.
@MainActor private final class PlaceDetailsRequest: NSObject, SearchEngineDelegate {
    private let engine = SearchEngine(locationProvider: nil, apiType: .searchBox)
    private var completion: ((any SearchResult)?) -> Void
    init(completion: @escaping ((any SearchResult)?) -> Void) {
        self.completion = completion
        super.init()
        engine.delegate = self
    }
    func start(_ mapboxID: String) {
        engine.retrieve(mapboxID: mapboxID, options: DetailsOptions(attributeSets: [.basic, .photos, .visit]))
    }
    func suggestionsUpdated(suggestions: [any SearchSuggestion], searchEngine: SearchEngine) { }
    func resultResolved(result: any SearchResult, searchEngine: SearchEngine) { completion(result) }
    func resultsResolved(results: [any SearchResult], searchEngine: SearchEngine) { completion(results.first) }
    func searchErrorHappened(searchError: SearchError, searchEngine: SearchEngine) { completion(nil) }
}
