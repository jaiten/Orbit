import XCTest

final class ChecklistUITests: XCTestCase {
    func testInlineCaptureAddsMultipleItemsWithoutASheet() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let input = app.textFields["task-title-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("Buy coffee\n")
        XCTAssertTrue(app.buttons["Complete Buy coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["Save"].exists)
        input.typeText("Walk every day\n")
        XCTAssertTrue(app.buttons["Log Walk"].waitForExistence(timeout: 5))
        input.typeText("\n")
        XCTAssertEqual(app.buttons.matching(identifier: "Complete Buy coffee").count, 1)
        XCTAssertTrue(app.buttons["Dictate task"].exists)
    }

    func testMenuConversionAndSwipeDelete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let addButton = app.buttons["Task options"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-title-input").firstMatch
        // The first launch on a cold simulator can swallow the first tap; try once more.
        if !field.waitForExistence(timeout: 5) { addButton.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Read a few pages")
        app.navigationBars.buttons["Save"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "checklist-title").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.press(forDuration: 1.2)
        let makeHabit = app.buttons["Make It a Habit"]
        XCTAssertTrue(makeHabit.waitForExistence(timeout: 5)); makeHabit.tap()
        XCTAssertTrue(app.buttons["Log Read a few pages"].waitForExistence(timeout: 5))
        app.buttons["Edit Read a few pages"].press(forDuration: 1.2)
        let makeTask = app.buttons["Make It a Task"]
        XCTAssertTrue(makeTask.waitForExistence(timeout: 5)); makeTask.tap()
        XCTAssertTrue(app.buttons["Complete Read a few pages"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Orbit Today checklist"; screenshot.lifetime = .keepAlways; add(screenshot)
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        // Wait for disappearance directly. Negating waitForExistence times out and
        // collects diagnostics, which can consume the eight-second Undo window.
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2)); undo.tap()
        XCTAssertTrue(app.buttons["Complete Read a few pages"].waitForExistence(timeout: 5))
    }
    func testTickCompletesAndRowOpens() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let addButton = app.buttons["Task options"]
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
        // One row per item, stacked, as on the website.
        XCTAssertEqual(app.buttons["Complete Clean the car"].frame.minX, app.buttons["Complete Call Mom"].frame.minX, accuracy: 2)
        XCTAssertNotEqual(app.buttons["Complete Clean the car"].frame.minY, app.buttons["Complete Call Mom"].frame.minY)
        // The tick completes; the rest of the row opens the item.
        let toggle = app.buttons["Complete Clean the car"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        toggle.tap()
        let completed = app.buttons["Completed (1)"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        reveal(completed, in: app); completed.tap()
        let reopen = app.buttons["Reopen Clean the car"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reveal(reopen, in: app); reopen.tap()
        XCTAssertTrue(app.buttons["Complete Clean the car"].waitForExistence(timeout: 5))
        reveal(app.buttons["Edit Call Mom"], in: app)
        app.buttons["Edit Call Mom"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Completed checklist tile"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testHabitTitleEditsAndCheckLogsOnTodayAndHabits() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Add a habit"].waitForExistence(timeout: 15))
        app.buttons["Add a habit"].tap()
        let field = app.textFields["habit-title-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Stretch")
        app.navigationBars.buttons["Save"].tap()
        let edit = app.buttons["Edit Stretch"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        let log = app.buttons["Log Stretch"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(log.frame.width, 44)
        XCTAssertGreaterThanOrEqual(log.frame.height, 44)
        log.tap()
        let completed = app.buttons["Completed (1)"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        reveal(completed, in: app); completed.tap()
        let undo = app.buttons["Undo Stretch"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); reveal(undo, in: app); undo.tap()
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        app.tabBars.buttons["Habits"].tap()
        app.buttons["Edit Stretch"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(log.waitForExistence(timeout: 5)); log.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
    }

    func testReturnSavesAndKeepsCaptureOpen() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Task options"].waitForExistence(timeout: 15))
        app.buttons["Task options"].tap()
        let field = app.textFields["task-title-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Buy coffee\n")
        let receipt = app.staticTexts["quick-add-receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.label.contains("Buy coffee"))
        XCTAssertEqual(field.value as? String, "What do you need to do?")
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled)
        // Another Return on an empty field must not create a blank item or dismiss.
        field.typeText("\n")
        XCTAssertTrue(field.exists)
        field.typeText("Call the dentist\n")
        let secondReceipt = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Call the dentist"), object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [secondReceipt], timeout: 5), .completed)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Complete Buy coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Complete Call the dentist"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Complete Buy coffee").count, 1)
    }

    func testReturnPreservesListContext() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Lists"].tap()
        app.buttons["New task"].tap()
        let field = app.textFields["task-title-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Choose a book\n")
        field.typeText("Visit the library")
        XCTAssertFalse(app.staticTexts["quick-add-preview"].label.contains("Today"))
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Complete Choose a book"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Complete Visit the library"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["Complete Choose a book"].exists)
        XCTAssertFalse(app.buttons["Complete Visit the library"].exists)
    }

    func testListsPlusCreatesAListAndTasksHaveCollapsibleGroups() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: 15)); app.tabBars.buttons["Lists"].tap()
        app.buttons["New list"].tap()
        let alert = app.alerts["New list"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Weekend")
        alert.buttons["Create list"].tap()
        app.buttons["New task"].tap()
        let input = app.textFields["task-title-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Choose a trail")
        app.navigationBars.buttons["Save"].tap()
        let task = app.buttons["Complete Choose a trail"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        let group = app.buttons["No date (1)"]
        XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
        XCTAssertFalse(task.isHittable)
        group.tap(); XCTAssertTrue(task.waitForExistence(timeout: 5))
        app.buttons["Edit Lists"].tap()
        XCTAssertTrue(app.textFields["new-list-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].exists)
        app.textFields["new-list-name"].tap(); app.textFields["new-list-name"].typeText("Errands")
        app.buttons["Add List"].tap()
        app.buttons["Reorder Errands"].tap(); app.buttons["Move up"].tap()
        let names = app.textFields.allElementsBoundByIndex.compactMap { $0.value as? String }
        XCTAssertLessThan(try! XCTUnwrap(names.firstIndex(of: "Errands")), try! XCTUnwrap(names.firstIndex(of: "Weekend")))
        app.navigationBars.buttons["Done"].tap()
    }

    func testCalendarMakesAddingToAnotherDayExplicit() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 15)); app.tabBars.buttons["Calendar"].tap()
        app.buttons["Next week"].tap()
        let add = app.buttons["calendar-add-task"]
        reveal(add, in: app); add.tap()
        let input = app.textFields["task-title-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Pick up a parcel")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Complete Pick up a parcel"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["Complete Pick up a parcel"].exists)
        app.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(app.buttons["Upcoming (1)"].waitForExistence(timeout: 5))
    }

    func testLargeTextAndCompactRowsKeepReadableControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15)); app.tabBars.buttons["Settings"].tap()
        let compact = app.switches["Compact habits and tasks"]
        reveal(compact, in: app); XCTAssertTrue(compact.exists)
        if compact.value as? String == "0" { compact.tap() }
        app.tabBars.buttons["Today"].tap()
        app.buttons["Add a habit"].tap()
        let title = app.textFields["habit-title-input"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Take a walk outside and get some fresh air")
        app.navigationBars.buttons["Save"].tap()
        let check = app.buttons["Log Take a walk outside and get some fresh air"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); reveal(check, in: app)
        XCTAssertGreaterThanOrEqual(check.frame.width, 44)
        XCTAssertGreaterThanOrEqual(check.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Today at largest text size"; screenshot.lifetime = .keepAlways; add(screenshot)
        check.tap()
        XCTAssertTrue(app.buttons["Completed (1)"].waitForExistence(timeout: 5))
        // Leave the user's default row density for following tests.
        app.tabBars.buttons["Settings"].tap(); reveal(compact, in: app)
        if compact.value as? String == "1" { compact.tap() }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }

    func testNativeThemeMenusAndHabitHistory() {
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
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 5)); app.buttons["History"].tap()
        // Every habit's history is on one screen; Check-ins opens the full list for one.
        XCTAssertTrue(app.staticTexts["A small routine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of the last 7 days"].exists)
        app.buttons["Check-ins"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["A small routine"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap(); reveal(app.buttons["Coral"], in: app); app.buttons["Coral"].tap()
        app.buttons["Appearance"].tap(); app.buttons["System"].tap()
        // Account has its own screen.
        app.swipeDown(); app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Account")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign in"].exists)
    }

    func testQuickAddPreviewCreatesHabit() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let addButton = app.buttons["Task options"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15)); addButton.tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-title-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Stretch every day 7am")
        let chip = app.staticTexts["quick-add-preview"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(chip.label.hasPrefix("Habit · Daily · 7:00"), chip.label)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Log Stretch")).firstMatch.waitForExistence(timeout: 5))
    }

    func testTodayWithSampleDataScreenshot() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--onboarding"]; app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Orbit"].waitForExistence(timeout: 15))
        let input = app.textFields["onboarding-input"]; input.tap(); input.typeText("dentist tomorrow 9am")
        XCTAssertTrue(app.staticTexts["onboarding-preview"].waitForExistence(timeout: 5))
        app.buttons["Try example tasks"].tap()
        XCTAssertTrue(app.staticTexts["Choose your first habits"].waitForExistence(timeout: 5))
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.staticTexts["Use Orbit on your devices"].waitForExistence(timeout: 5))
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.buttons["Add a task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Complete Morning walk")).firstMatch.waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Orbit Today screenshot"; image.lifetime = .keepAlways; add(image)
        app.tabBars.buttons["Settings"].tap()
        let remove = app.buttons["Remove Examples"]
        reveal(remove, in: app); remove.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Complete Morning walk")).firstMatch.waitForExistence(timeout: 2))
    }

}
