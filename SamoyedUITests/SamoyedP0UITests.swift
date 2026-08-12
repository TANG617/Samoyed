import XCTest

final class SamoyedP0UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = "empty"
        app.launchEnvironment["SAMOYED_UI_TEST_RESET"] = "1"
    }

    func testActivationNowUndoAndPersistence() throws {
        app.launch()

        XCTAssertTrue(app.navigationBars["Set Up Samoyed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["day-type-name"].value as? String, "Workday")
        app.buttons["activation-start"].tap()

        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        let taskButton = app.buttons["Review progress"]
        XCTAssertTrue(taskButton.waitForExistence(timeout: 5))
        taskButton.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
        app.buttons["Undo"].tap()

        app.terminate()
        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = "empty"
        relaunchedApp.launchEnvironment["SAMOYED_UI_TEST_RESET"] = "0"
        app = relaunchedApp
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Set Up Samoyed"].exists)
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
        let existingTitle = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingTitle.count))
        let correctedTitle = "Afternoon Updated"
        title.typeText(correctedTitle)
        let titleCommitted = expectation(
            for: NSPredicate(format: "value == %@", correctedTitle),
            evaluatedWith: title
        )
        wait(for: [titleCommitted], timeout: 3)
        app.buttons["today-correction-save"].tap()

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        let updatedAfternoon = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon Updated")
        ).firstMatch
        XCTAssertTrue(updatedAfternoon.waitForExistence(timeout: 5))
    }

    func testLoadErrorDoesNotFallBackToSampleData() throws {
        app.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = "load-error"
        app.launch()

        XCTAssertTrue(app.staticTexts["Unable to Open Your Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertFalse(app.tabBars.buttons["Now"].exists)
        XCTAssertFalse(app.navigationBars["Set Up Samoyed"].exists)
    }

    func testLibraryDayTypeManagementPath() throws {
        app.launch()
        XCTAssertTrue(app.buttons["activation-start"].waitForExistence(timeout: 5))
        app.buttons["activation-start"].tap()

        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5))
        libraryTab.tap()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let workday = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Workday")
        ).firstMatch
        XCTAssertTrue(workday.waitForExistence(timeout: 5))
        workday.tap()
        XCTAssertTrue(app.navigationBars["Workday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].exists)
    }

    func testAccessibilityIdentifiersSurviveLargeDynamicType() throws {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Set Up Samoyed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["day-type-name"].exists)
        let start = app.buttons["activation-start"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(start.isHittable)
        start.tap()

        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["now-today-different"].exists)
    }

    @MainActor
    func testVoiceOverKeepsCriticalAccessibilityIdentifiersReachable() throws {
        app.launch()

        XCTAssertTrue(app.navigationBars["Set Up Samoyed"].waitForExistence(timeout: 5))
        let nameField = app.textFields["day-type-name"]
        let startButton = app.buttons["activation-start"]
        XCTAssertTrue(nameField.exists)
        XCTAssertTrue(startButton.exists)

        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let voiceOver = XCUIDevice.shared.voiceOverService
            try voiceOver.enable()
            addTeardownBlock {
                try voiceOver.disable()
            }
            XCTAssertTrue(voiceOver.isEnabled)
            XCTAssertFalse(try voiceOver.currentSpeech().utterance.isEmpty)
        }
        #endif

        XCTAssertTrue(app.textFields["day-type-name"].exists)
        XCTAssertTrue(app.buttons["activation-start"].exists)
    }
}
