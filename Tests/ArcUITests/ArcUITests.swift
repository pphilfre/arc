import XCTest

final class ArcUITests: XCTestCase {
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
