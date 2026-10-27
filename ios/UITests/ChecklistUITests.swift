import XCTest

final class ChecklistUITests: XCTestCase {
    func testSuggestedStartAndFinishForLaundry() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let input = app.textViews["inline-task-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("Laundry\n")
        let options = app.buttons["Progress options for Laundry"]
        XCTAssertTrue(options.waitForExistence(timeout: 5)); options.tap()
        let suggestion = app.buttons["Track start & finish"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        let start = app.buttons["Start Laundry"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(start.frame.midY, app.buttons["Edit Laundry"].frame.midY, accuracy: 2)
        let height = app.buttons["Edit Laundry"].frame.height
        start.tap()
        XCTAssertEqual(app.buttons["Edit Laundry"].value as? String, "In progress")
        let finish = app.buttons["Finish Laundry"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertEqual(finish.frame.midY, app.buttons["Edit Laundry"].frame.midY, accuracy: 2)
        XCTAssertEqual(app.buttons["Edit Laundry"].frame.height, height, accuracy: 2)
        // Starting suggests a timer once; it can be declined.
        XCTAssertTrue(app.buttons["Start a 30-min timer"].waitForExistence(timeout: 5))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Start a 30-min timer"].waitForNonExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Orbit inline task progress"; screenshot.lifetime = .keepAlways; add(screenshot)
        finish.tap()
        XCTAssertTrue(app.buttons["Completed (1)"].waitForExistence(timeout: 5))
    }

    func testCaptureSitsUnderThePlanAndKeepsDraftWhenKeyboardCloses() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let input = app.textViews["inline-task-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(input.frame.height, 44)
        XCTAssertLessThan(input.frame.maxY, app.frame.height * 0.6)
        let idle = XCTAttachment(screenshot: app.screenshot())
        idle.name = "Today capture under the plan"; idle.lifetime = .keepAlways; add(idle)
        input.tap(); input.typeText("Pay bill\n")
        XCTAssertTrue(app.buttons["Complete Pay bill"].waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 2)
        input.typeText("Call mum")
        // The preview chip is opaque and belongs to the keyboard.
        XCTAssertTrue(app.staticTexts["quick-add-preview"].waitForExistence(timeout: 5))
        let typing = XCTAttachment(screenshot: app.screenshot())
        typing.name = "Today capture above keyboard"; typing.lifetime = .keepAlways; add(typing)
        app.buttons["Dismiss keyboard"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quick-add-preview"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Call mum")
        app.tabBars.buttons["Notes"].tap(); app.tabBars.buttons["Today"].tap()
        XCTAssertEqual(input.value as? String, "Call mum")
        app.buttons["Add a task"].tap()
        XCTAssertTrue(app.buttons["Complete Call mum"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Complete Call mum").count, 1)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        app.buttons["Dismiss keyboard"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        app.buttons["Edit Call mum"].press(forDuration: 1.2)
        app.buttons["Delete"].tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(app.buttons["Complete Call mum"].waitForExistence(timeout: 5))
    }

    func testInlineCaptureAddsMultipleItemsWithoutASheet() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let input = app.textViews["inline-task-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("Buy coffee\n")
        XCTAssertTrue(app.buttons["Complete Buy coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["Save"].exists)
        input.typeText("Walk every day\n")
        XCTAssertTrue(app.buttons["Log Walk"].waitForExistence(timeout: 5))
        // Return on an empty field means "done": it closes the keyboard without adding anything.
        input.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Complete Buy coffee").count, 1)
        XCTAssertTrue(app.buttons["Dictate task"].exists)
    }

    func testLongCaptureBecomesANote() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let input = app.textViews["inline-task-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        let short = input.frame.height
        input.tap()
        input.typeText("Garden ideas. Plant tomatoes along the south fence, move the herbs closer to the kitchen door so they get used more often, and build a frame for the beans before the weekend")
        let chip = app.staticTexts["quick-add-preview"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.label.hasPrefix("Note"), chip.label)
        XCTAssertGreaterThan(input.frame.height, short + 10)
        let typing = XCTAttachment(screenshot: app.screenshot())
        typing.name = "Long capture grows into a note"; typing.lifetime = .keepAlways; add(typing)
        input.typeText("\n")
        XCTAssertEqual(input.value as? String, "")
        XCTAssertFalse(app.buttons["Complete Garden ideas"].waitForExistence(timeout: 2))
        app.buttons["Dismiss keyboard"].tap()
        app.tabBars.buttons["Notes"].tap()
        let note = app.buttons["Garden ideas"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        note.tap()
        XCTAssertTrue(app.textViews["note-body"].waitForExistence(timeout: 5) || app.textFields["note-body"].waitForExistence(timeout: 2))
        let page = XCTAttachment(screenshot: app.screenshot())
        page.name = "Note page"; page.lifetime = .keepAlways; add(page)
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
        reveal(completed, in: app); if completed.value as? String != "Expanded" { completed.tap() }
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
        reveal(completed, in: app); if completed.value as? String != "Expanded" { completed.tap() }
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
        let field = app.textViews["task-title-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Buy coffee\n")
        // No success message: the field simply clears for the next item.
        XCTAssertFalse(app.staticTexts["quick-add-receipt"].exists)
        XCTAssertEqual(field.value as? String, "")
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled)
        // Return on an empty field must not create a blank item or dismiss the sheet; it closes the keyboard.
        field.typeText("\n")
        XCTAssertTrue(field.exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        field.tap(); field.typeText("Call the dentist\n")
        XCTAssertEqual(field.value as? String, "")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Complete Buy coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Complete Call the dentist"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Complete Buy coffee").count, 1)
    }

    func testNotesHaveSectionsAndPages() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Notes"].waitForExistence(timeout: 15)); app.tabBars.buttons["Notes"].tap()
        let sections = app.buttons["edit-sections"]
        XCTAssertTrue(sections.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(sections.frame.height, 44)
        sections.tap()
        XCTAssertTrue(app.textFields["new-list-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].exists)
        for name in ["Weekend", "Errands"] {
            app.textFields["new-list-name"].tap(); app.textFields["new-list-name"].typeText(name)
            app.buttons["Add Section"].tap()
        }
        app.buttons["Reorder Errands"].tap(); app.buttons["Move up"].tap()
        let names = app.textFields.allElementsBoundByIndex.compactMap { $0.value as? String }
        XCTAssertLessThan(try! XCTUnwrap(names.firstIndex(of: "Errands")), try! XCTUnwrap(names.firstIndex(of: "Weekend")))
        app.navigationBars.buttons["Done"].tap()
        app.buttons["New note in Weekend"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "note-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Trail options")
        let body = app.descendants(matching: .any).matching(identifier: "note-body").firstMatch
        body.tap(); body.typeText("Ridge loop or the lake path")
        let page = XCTAttachment(screenshot: app.screenshot())
        page.name = "New note page"; page.lifetime = .keepAlways; add(page)
        let back = app.navigationBars.buttons["Notes"]
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let row = app.buttons["Trail options"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "Notes with sections"; list.lifetime = .keepAlways; add(list)
        row.press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["Copy text"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["Copy text"].tap()
        // Notes never appear as to-dos.
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["Complete Trail options"].exists)
    }

    func testCalendarMakesAddingToAnotherDayExplicit() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 15)); app.tabBars.buttons["Calendar"].tap()
        app.buttons["Next week"].tap()
        let add = app.buttons["calendar-add-task"]
        reveal(add, in: app); add.tap()
        let input = app.textViews["task-title-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Pick up a parcel")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Complete Pick up a parcel"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["Complete Pick up a parcel"].exists)
        // The wider views show it: everything, grouped by when.
        app.buttons["today-scope"].tap()
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["Complete Pick up a parcel"].waitForExistence(timeout: 5))
        let everything = XCTAttachment(screenshot: app.screenshot())
        everything.name = "Today showing everything"; everything.lifetime = .keepAlways; self.add(everything)
        app.buttons["today-scope"].tap()
        app.buttons["Day"].tap()
        XCTAssertFalse(app.buttons["Complete Pick up a parcel"].waitForExistence(timeout: 2))
    }

    func testLargeTextAndCompactRowsKeepReadableControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15)); app.tabBars.buttons["Settings"].tap()
        XCTAssertGreaterThan(app.staticTexts["Preferences"].frame.minX, 0)
        let settingsImage = XCTAttachment(screenshot: app.screenshot())
        settingsImage.name = "Settings at largest text size"; settingsImage.lifetime = .keepAlways; add(settingsImage)
        app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.buttons["edit-sections"].isHittable)
        let listsImage = XCTAttachment(screenshot: app.screenshot())
        listsImage.name = "Notes at largest text size"; listsImage.lifetime = .keepAlways; add(listsImage)
        app.tabBars.buttons["Settings"].tap()
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
        app.tabBars.buttons["Habits"].tap()
        let history = app.buttons["History"]; reveal(history, in: app); history.tap()
        let historyImage = XCTAttachment(screenshot: app.screenshot())
        historyImage.name = "Habit history at largest text size"; historyImage.lifetime = .keepAlways; add(historyImage)
        // Leave the user's default row density for following tests.
        app.tabBars.buttons["Settings"].tap(); reveal(compact, in: app)
        if compact.value as? String == "1" { compact.tap() }
    }

    func testTodayRemembersCompletedAcrossRelaunches() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        func addCompletedTask() {
            let input = app.textViews["inline-task-input"]
            XCTAssertTrue(input.waitForExistence(timeout: 15))
            input.tap(); input.typeText("Remember this task\n")
            app.buttons["Dismiss keyboard"].tap()
            let complete = app.buttons["Complete Remember this task"]
            XCTAssertTrue(complete.waitForExistence(timeout: 5)); complete.tap()
        }
        app.launch(); addCompletedTask()
        let disclosure = app.buttons["Completed (1)"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5)); reveal(disclosure, in: app)
        if disclosure.value as? String != "Expanded" { disclosure.tap() }
        XCTAssertTrue(app.buttons["Reopen Remember this task"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); addCompletedTask()
        XCTAssertTrue(app.buttons["Reopen Remember this task"].waitForExistence(timeout: 5))
        reveal(disclosure, in: app); disclosure.tap()
        app.terminate(); app.launch(); addCompletedTask()
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["Reopen Remember this task"].exists)
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
        let historyImage = XCTAttachment(screenshot: app.screenshot())
        historyImage.name = "Rounded habit history"; historyImage.lifetime = .keepAlways; add(historyImage)
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
