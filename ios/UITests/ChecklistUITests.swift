import XCTest

final class ChecklistUITests: XCTestCase {
    func testSwipeConversionAndDelete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let addButton = app.buttons["Add to-do or non-negotiable"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        app.buttons["To-do"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-title-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Read a few pages")
        app.navigationBars.buttons["Save"].tap()
        let row = app.cells.containing(.staticText, identifier: "Read a few pages").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        let makeHabit = app.buttons["Make non-negotiable"]
        XCTAssertTrue(makeHabit.waitForExistence(timeout: 5)); makeHabit.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Log Read a few pages")).firstMatch.waitForExistence(timeout: 5))
        row.swipeRight()
        let makeTask = app.buttons["Make to-do"]
        XCTAssertTrue(makeTask.waitForExistence(timeout: 5)); makeTask.tap()
        XCTAssertTrue(app.buttons["Complete Read a few pages"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Orbit Today checklist"; screenshot.lifetime = .keepAlways; add(screenshot)
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertFalse(app.staticTexts["Read a few pages"].waitForExistence(timeout: 2))
    }
}
