import XCTest
import CoreLocation
import SwiftUI
@testable import Arc

final class ArcTests: XCTestCase {
    @MainActor func testDismissingCategoryKeepsSavedAndDeliberatePins() {
        let model = ArcModel()
        let saved = Place.pin(at: .init(latitude: 51, longitude: 0), name: "Saved")
        let pin = Place.pin(at: .init(latitude: 52, longitude: 0))
        let result = Place.pin(at: .init(latitude: 53, longitude: 0), name: "Food result")
        model.savedMarkers = [saved]; model.droppedPins = [pin]
        model.searching = true; model.search.activeCategory = SearchCategory.all.first
        model.search.places = [result]
        XCTAssertEqual(model.annotations.count, 3)
        model.dismissSearch()
        XCTAssertEqual(Set(model.annotations.map(\.id)), [saved.id, pin.id])
        XCTAssertNil(model.search.activeCategory)
        XCTAssertTrue(model.search.places.isEmpty)
    }
    func testOpeningHoursAcrossMidnightAndSplitPeriods() {
        let schedule = OpeningSchedule(availability: .scheduled, periods: [
            .init(weekday: 2, startMinute: 8 * 60, endWeekday: 2, endMinute: 12 * 60),
            .init(weekday: 2, startMinute: 18 * 60, endWeekday: 3, endMinute: 2 * 60)
        ], timeZoneIdentifier: "Europe/London")
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(schedule.status(at: formatter.date(from: "2026-10-05T10:00:00Z")!), "Open now · Closes 12:00")
        XCTAssertEqual(schedule.status(at: formatter.date(from: "2026-10-05T14:00:00Z")!), "Closed now")
        XCTAssertEqual(schedule.status(at: formatter.date(from: "2026-10-06T00:00:00Z")!), "Open now · Closes 02:00")
        XCTAssertEqual(schedule.hours(for: 2), "08:00 – 12:00, 18:00 – 02:00")
        XCTAssertEqual(schedule.hours(for: 4), "Closed")
    }
    func testNaturalAddressFormattingPreservesExistingNames() {
        XCTAssertEqual(AddressFormatting.natural("10 high street, newcastle upon tyne, sw1a 1aa"), "10 High Street, Newcastle upon Tyne, SW1A 1AA")
        XCTAssertEqual(AddressFormatting.natural("McDonald's, iPhone Store, UK"), "McDonald's, iPhone Store, UK")
    }
    func testTemporaryAnnotationsDoNotReplaceRetainedPins() {
        let place = Place.pin(at: .init(latitude: 51, longitude: 0))
        let retained = ArcAnnotation(place: place, role: .dropped)
        let selected = ArcAnnotation(place: place, role: .selected)
        XCTAssertEqual(ArcAnnotation.merge([[retained], [selected]]).first?.role, .selected)
        XCTAssertEqual(ArcAnnotation.merge([[retained], []]).first?.role, .dropped)
    }
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
