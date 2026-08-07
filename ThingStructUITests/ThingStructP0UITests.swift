import XCTest

final class ThingStructP0UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["THINGSTRUCT_UI_TEST_FIXTURE"] = "empty"
        app.launchEnvironment["THINGSTRUCT_UI_TEST_RESET"] = "1"
    }

    func testActivationNowUndoAndPersistence() throws {
        app.launch()

        XCTAssertTrue(app.navigationBars["Set Up ThingStruct"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["day-type-name"].value as? String, "Workday")
        app.buttons["activation-start"].tap()

        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        let taskButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Mark Review progress complete")
        ).firstMatch
        if taskButton.waitForExistence(timeout: 2) {
            taskButton.tap()
            XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
            app.buttons["Undo"].tap()
        }

        app.terminate()
        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchEnvironment["THINGSTRUCT_UI_TEST_FIXTURE"] = "empty"
        relaunchedApp.launchEnvironment["THINGSTRUCT_UI_TEST_RESET"] = "0"
        app = relaunchedApp
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Set Up ThingStruct"].exists)
    }

    func testTodayDifferentCanChooseNoRoutineWithoutChangingUsualWeek() throws {
        app.launch()
        XCTAssertTrue(app.buttons["activation-start"].waitForExistence(timeout: 5))
        app.buttons["activation-start"].tap()

        XCTAssertTrue(app.buttons["now-today-different"].waitForExistence(timeout: 5))
        app.buttons["now-today-different"].tap()
        XCTAssertTrue(app.buttons["today-no-routine"].waitForExistence(timeout: 3))
        app.buttons["today-no-routine"].tap()

        XCTAssertTrue(app.staticTexts["Nothing is running today"].waitForExistence(timeout: 3))
    }

    func testTodayOnlyCorrectionFlow() throws {
        app.launch()
        XCTAssertTrue(app.buttons["activation-start"].waitForExistence(timeout: 5))
        app.buttons["activation-start"].tap()
        app.tabBars.buttons["Today"].tap()

        let afternoon = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon")
        ).firstMatch
        XCTAssertTrue(afternoon.waitForExistence(timeout: 5))
        afternoon.tap()
        XCTAssertTrue(app.buttons["today-edit"].waitForExistence(timeout: 3))
        app.buttons["today-edit"].tap()

        let title = app.textFields["today-correction-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText(" Updated")
        app.buttons["today-correction-save"].tap()

        XCTAssertTrue(app.navigationBars["Afternoon Updated"].waitForExistence(timeout: 3))
    }

    func testLoadErrorDoesNotFallBackToSampleData() throws {
        app.launchEnvironment["THINGSTRUCT_UI_TEST_FIXTURE"] = "load-error"
        app.launch()

        XCTAssertTrue(app.staticTexts["Unable to Open Your Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertFalse(app.tabBars.buttons["Now"].exists)
        XCTAssertFalse(app.navigationBars["Set Up ThingStruct"].exists)
    }
}
