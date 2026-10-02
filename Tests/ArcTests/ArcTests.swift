import XCTest
import CoreLocation
import SwiftUI
@testable import Arc

final class ArcTests: XCTestCase {
    func testUnitsAndUnknownSpeed() {
        XCTAssertEqual(SpeedUnit.mph.speed(26.8224), 60)
        XCTAssertEqual(SpeedUnit.kmh.speed(10), 36)
        XCTAssertEqual(SpeedUnit.mph.speed(-1), 0)
        XCTAssertEqual(SpeedUnit.mph.speed(.nan), 0)
        XCTAssertEqual(SpeedUnit.mph.speed(.infinity), 0)
        XCTAssertEqual(SpeedUnit.mph.distance(1609.344), "1.0 mi")
        XCTAssertEqual(SpeedUnit.kmh.distance(1000), "1.0 km")
    }
    func testPlaceRoundTripRetainsCoordinateAndContactDetails() throws {
        var place = Place.pin(at: .init(latitude: 51.5, longitude: -0.1), name: "A place")
        place.phone = "+44 12345"
        place.website = URL(string: "https://example.com")
        let decoded = try JSONDecoder().decode(Place.self, from: JSONEncoder().encode(place))
        XCTAssertEqual(place, decoded)
    }
    func testMovementRejectsImpossibleJumpAndStationaryJitter() {
        var session = MovementSession()
        let date = Date()
        func fix(_ latitude: Double, speed: Double, seconds: Double) -> CLLocation {
            .init(coordinate: .init(latitude: latitude, longitude: 0), altitude: 10,
                  horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: speed,
                  timestamp: date.addingTimeInterval(seconds))
        }
        session.record(fix(51, speed: 0, seconds: 0))
        session.record(fix(51.00001, speed: 0, seconds: 1))
        XCTAssertEqual(session.distance, 0)
        session.record(fix(52, speed: 10, seconds: 2))
        XCTAssertEqual(session.distance, 0)
        session.record(fix(52.0001, speed: 10, seconds: 3))
        XCTAssertGreaterThan(session.distance, 5)
        XCTAssertLessThan(session.distance, 20)
    }
    @MainActor func testPreferencesAreLocalAndPersistAcrossInstances() {
        let suite = "arc-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Preferences(defaults: defaults)
        first.accent = .purple; first.avoidTolls = true; first.voice = .muted
        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.accent, .purple)
        XCTAssertTrue(second.avoidTolls)
        XCTAssertEqual(second.voice, .muted)
    }
    @MainActor func testSettingsBindingsUpdateSharedPreferencesAndPersist() {
        let suite = "arc-bindings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = Preferences(defaults: defaults)
        @Bindable var preferences = shared

        $preferences.avoidTolls.wrappedValue = true
        $preferences.voice.wrappedValue = .muted
        $preferences.buildings.wrappedValue = true
        $preferences.accent.wrappedValue = .purple

        XCTAssertTrue(shared.avoidTolls)
        XCTAssertEqual(shared.voice, .muted)
        XCTAssertTrue(shared.buildings)
        XCTAssertEqual(shared.accent, .purple)
        let restored = Preferences(defaults: defaults)
        XCTAssertTrue(restored.avoidTolls)
        XCTAssertEqual(restored.voice, .muted)
        XCTAssertTrue(restored.buildings)
        XCTAssertEqual(restored.accent, .purple)
    }
}
