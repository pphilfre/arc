import XCTest

final class ArcUITests: XCTestCase {
    @MainActor func testSettingsAndLayersRemainAligned() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Profile and settings"].waitForExistence(timeout: 20))
        capture("Browsing controls", app: app)
        app.buttons["Profile and settings"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Purple"].waitForExistence(timeout: 5))
        app.buttons["Purple"].tap()
        capture("Accent presets", app: app)
        app.buttons["Done"].tap()
        app.buttons["Map layers"].tap()
        XCTAssertTrue(app.buttons["map.style.satellite"].waitForExistence(timeout: 5))
        app.buttons["map.style.satellite"].tap()
        app.buttons["map.style.default"].tap()
        let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Selected'"),
            object: app.buttons["map.style.default"])
        XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 25), .completed)
        capture("Layers after rapid style switching", app: app)
    }
    @MainActor func testSearchKeepsOnePositionThroughKeyboardAndClearsCategories() {
        let app = XCUIApplication()
        app.launch()
        let search = app.buttons["map.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let done = app.buttons["search.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let field = app.textFields["search.query"]
        let before = field.frame.minY
        capture("Search before keyboard", app: app)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("coffee")
        XCTAssertEqual(field.frame.minY, before, accuracy: 3, "Keyboard must resize results, not move the search surface")
        capture("Search with keyboard", app: app)
        app.buttons["Clear search"].tap()
        app.buttons["Food"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Clear category"].waitForExistence(timeout: 5))
        capture("Active category and clear action", app: app)
        app.buttons["Clear category"].tap()
        XCTAssertFalse(app.buttons["Clear category"].exists)
        done.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["search.query"].exists)
    }
    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
