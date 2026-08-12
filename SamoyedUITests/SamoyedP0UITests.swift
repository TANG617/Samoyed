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

    func testTodayTimelineIsAvailableAfterActivation() throws {
        app.launch()
        XCTAssertTrue(app.buttons["activation-start"].waitForExistence(timeout: 5))
        app.buttons["activation-start"].tap()
        app.tabBars.buttons["Today"].tap()

        let afternoon = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon")
        ).firstMatch
        XCTAssertTrue(afternoon.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(afternoon))
    }

    func testTodayBlockInspectorFlow() throws {
        app.launch()
        XCTAssertTrue(app.buttons["activation-start"].waitForExistence(timeout: 5))
        app.buttons["activation-start"].tap()
        app.tabBars.buttons["Today"].tap()

        let afternoon = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon")
        ).firstMatch
        XCTAssertTrue(afternoon.waitForExistence(timeout: 5))
        afternoon.tap()
        XCTAssertTrue(app.navigationBars["Block Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Checklist"].exists)
        XCTAssertTrue(app.staticTexts["Reminders"].exists)
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

    func testNowRendersSameLayerChecklistItemsInsideOneContinuousGroup() throws {
        app.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = "single-layer-days"
        app.launchEnvironment["SAMOYED_SIMULATION_MINUTE"] = "816"
        app.launch()

        let group = app.otherElements["now-checklist-group-layer-0-remaining"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertEqual(group.buttons.count, 2)
    }

    func testNextDayKeepsSingleLayerCurrentBlockInView() throws {
        app.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = "single-layer-days"
        app.launchEnvironment["SAMOYED_SIMULATION_MINUTE"] = "816"
        app.launch()
        app.tabBars.buttons["Today"].tap()

        let currentBlock = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon")
        ).firstMatch
        XCTAssertTrue(currentBlock.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(currentBlock))

        app.buttons["Next Day"].tap()

        let nextDayCurrentBlock = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon")
        ).firstMatch
        XCTAssertTrue(nextDayCurrentBlock.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(nextDayCurrentBlock))
    }

    func testElasticTimelineMatchesSharedFigmaCoordinatesAt1336() throws {
        app.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = "elastic-timeline"
        app.launchEnvironment["SAMOYED_SIMULATION_MINUTE"] = "816"
        app.launch()
        app.tabBars.buttons["Today"].tap()

        let afternoon = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Afternoon")
        ).firstMatch
        let projectWork = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Project Work")
        ).firstMatch
        let indicator = app.otherElements["today-current-time-indicator"]
        let hour13 = app.staticTexts["13:00"].firstMatch
        let hour14 = app.staticTexts["14:00"].firstMatch

        XCTAssertTrue(afternoon.waitForExistence(timeout: 5))
        XCTAssertTrue(projectWork.waitForExistence(timeout: 5))
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertTrue(hour13.waitForExistence(timeout: 5))
        XCTAssertTrue(hour14.waitForExistence(timeout: 5))

        XCTAssertEqual(hour14.frame.minY - hour13.frame.minY, 206, accuracy: 3)
        XCTAssertEqual(projectWork.frame.minY - afternoon.frame.minY, 68, accuracy: 3)
        XCTAssertEqual(indicator.frame.midY - projectWork.frame.minY, 82, accuracy: 3)
        XCTAssertTrue(projectWork.frame.contains(indicator.frame.center))
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

    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
