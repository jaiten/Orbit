import XCTest

final class ChecklistUITests: XCTestCase {
    func testDragConversionAndSwipeDelete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let addButton = app.buttons["Add something"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-title-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Read a few pages")
        app.navigationBars.buttons["Save"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "checklist-title").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        let routine = app.staticTexts["Your routine"]
        row.press(forDuration: 1.2, thenDragTo: routine)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Log Read a few pages")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Edit Read a few pages"].tap()
        XCTAssertTrue(app.textFields["habit-title-input"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        let habit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Log Read a few pages")).firstMatch
        habit.press(forDuration: 1.2, thenDragTo: app.staticTexts["For today"])
        XCTAssertTrue(app.buttons["Complete Read a few pages"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Orbit Today checklist"; screenshot.lifetime = .keepAlways; add(screenshot)
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2)); app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Complete Read a few pages"].waitForExistence(timeout: 5))
    }
    func testLargeTapTargetAndCompletedPlacement() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let addButton = app.buttons["Add something"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15)); addButton.tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-title-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Clean the car")
        app.navigationBars.buttons["Save"].tap()
        for title in ["Call Mom", "Wash car"] {
            addButton.tap()
            let input = app.descendants(matching: .any).matching(identifier: "task-title-input").firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(title)
            app.navigationBars.buttons["Save"].tap()
            XCTAssertTrue(app.buttons["Complete " + title].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(app.buttons["Complete Clean the car"].frame.minY, app.buttons["Complete Call Mom"].frame.minY, accuracy: 2)
        XCTAssertGreaterThan(abs(app.buttons["Complete Clean the car"].frame.minX - app.buttons["Complete Call Mom"].frame.minX), 20)
        let toggle = app.buttons["Complete Clean the car"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Reopen Clean the car"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Completed checklist tile"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }

    func testNativeThemeMenusAndSeparateHabitHistory() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15)); app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["Sage"], in: app); app.buttons["Sage"].tap()
        XCTAssertTrue(app.buttons["Sage, selected"].waitForExistence(timeout: 5))
        reveal(app.buttons["Appearance"], in: app); app.buttons["Appearance"].tap(); app.buttons["Light"].tap()
        XCTAssertEqual(app.buttons["Appearance"].value as? String, "Light")
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Sage appearance controls"; image.lifetime = .keepAlways; add(image)
        app.tabBars.buttons["Habits"].tap(); app.buttons["New habit"].tap()
        let title = app.textFields["habit-title-input"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("A small routine")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Habit history"].waitForExistence(timeout: 5)); app.buttons["Habit history"].tap()
        app.buttons["A small routine"].tap()
        XCTAssertTrue(app.navigationBars["A small routine"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap(); reveal(app.buttons["Coral"], in: app); app.buttons["Coral"].tap()
        app.buttons["Appearance"].tap(); app.buttons["System"].tap()
    }

    func testTodayWithSampleDataScreenshot() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15)); app.tabBars.buttons["Settings"].tap()
        let sample = app.buttons["Explore with sample data"]
        reveal(sample, in: app); sample.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["Add something"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Orbit Today screenshot"; image.lifetime = .keepAlways; add(image)
    }

}
