import Foundation
import XCTest

final class SamoyedP0UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if app?.state != .notRunning {
            app?.terminate()
        }
        app = nil
    }

    func testFirstRunStarterInstallsFrozenRuntimeAndPersists() throws {
        launch(fixture: .firstRun)

        XCTAssertTrue(element(id: ID.firstRun).waitForExistence(timeout: 5))
        let starter = app.buttons[ID.activationStarter]
        XCTAssertTrue(starter.waitForExistence(timeout: 5))
        starter.tap()

        let start = app.buttons[ID.activationStart]
        XCTAssertTrue(revealByScrolling(start))
        XCTAssertTrue(start.isEnabled)
        start.tap()

        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[ID.nowFeedback].waitForExistence(timeout: 5))

        app.terminate()
        launch(fixture: .firstRun, reset: false)

        XCTAssertTrue(app.tabBars.buttons["Now"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(id: ID.firstRun).exists)
        XCTAssertTrue(app.buttons[ID.nowFeedback].exists)
    }

    func testInlineImportValidatesAndConfirmsReadOnlyRoutine() throws {
        launch(fixture: .firstRun, route: inlineImportRoute)

        XCTAssertTrue(app.navigationBars["Import Routine"].waitForExistence(timeout: 5))
        let routineName = app.textFields["Routine name"]
        XCTAssertTrue(routineName.exists)
        XCTAssertEqual(routineName.value as? String, "Imported Focus")
        XCTAssertTrue(app.staticTexts["Validated Config"].exists)

        let importButton = app.buttons["Import"].firstMatch
        XCTAssertTrue(importButton.exists)
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()

        XCTAssertTrue(app.navigationBars["All Routines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Imported Focus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit"].exists)
    }

    func testNowFeedbackValidationAndOfflineSave() throws {
        launch(fixture: .feedbackValidation)

        let feedback = app.buttons[ID.nowFeedback]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()

        XCTAssertTrue(app.navigationBars["Give Feedback"].waitForExistence(timeout: 3))
        let save = app.buttons[ID.feedbackSave]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled, "Empty feedback must not be saved.")

        app.buttons[ID.feedbackGood].tap()
        XCTAssertTrue(waitUntilEnabled(save))
        save.tap()

        XCTAssertTrue(app.navigationBars["Saved on this iPhone"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                "Your feedback is safely stored on this iPhone. No feedback sync service is configured."
            ].exists
        )
        XCTAssertTrue(app.buttons[ID.feedbackDone].exists)
    }

    func testNowChecklistUndoPersistsAcrossRelaunch() throws {
        launch(fixture: .frozenRuntime)

        let task = app.buttons["Ship milestone"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(task.value as? String, "Not completed")
        task.tap()

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertEqual(task.value as? String, "Not completed")

        app.terminate()
        launch(fixture: .frozenRuntime, reset: false)
        let relaunchedTask = app.buttons["Ship milestone"]
        XCTAssertTrue(relaunchedTask.waitForExistence(timeout: 5))
        XCTAssertEqual(relaunchedTask.value as? String, "Not completed")
    }

    func testTodayTimelineOpensFrozenBlockInspector() throws {
        launch(fixture: .frozenRuntime)
        openTab("Today")

        XCTAssertTrue(app.buttons[ID.todayCurrentRoutine].waitForExistence(timeout: 5))
        let projectWork = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Project Work")
        ).firstMatch
        XCTAssertTrue(projectWork.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(projectWork))
        projectWork.tap()

        XCTAssertTrue(app.navigationBars["Project Work"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Checklist"].exists)
        XCTAssertTrue(app.staticTexts["Reminders"].exists)
        XCTAssertTrue(app.buttons[ID.blockFeedback].exists)
        XCTAssertTrue(app.buttons[ID.blockDone].exists)
    }

    func testTodayChooserCanChooseNoRoutineAndRestoreWorkday() throws {
        launch(fixture: .frozenRuntime)
        openTab("Today")

        let currentRoutine = app.buttons[ID.todayCurrentRoutine]
        XCTAssertTrue(currentRoutine.waitForExistence(timeout: 5))
        currentRoutine.tap()

        let noRoutine = app.buttons[ID.todayNoRoutine]
        XCTAssertTrue(noRoutine.waitForExistence(timeout: 3))
        noRoutine.tap()

        XCTAssertTrue(app.staticTexts["No Routine Selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue("No Routine", of: currentRoutine))

        currentRoutine.tap()
        let select = app.buttons["Select for Today"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        select.tap()

        XCTAssertTrue(waitForValue("Workday", of: currentRoutine))
        XCTAssertFalse(app.staticTexts["No Routine Selected"].exists)
    }

    func testLibraryRoutinesAreReadOnlyAndAddressableByStableID() throws {
        launch(fixture: .frozenRuntime)
        openTab("Library")

        let current = app.buttons[ID.libraryCurrentRoutine]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.tap()

        XCTAssertTrue(app.navigationBars["Workday"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[ID.routineSelectToday].exists)
        XCTAssertFalse(app.buttons[ID.routineSelectToday].isEnabled)
        XCTAssertFalse(app.buttons["Edit"].exists)

        app.navigationBars.buttons["Library"].tap()
        app.buttons["All Routines"].tap()
        XCTAssertTrue(app.navigationBars["All Routines"].waitForExistence(timeout: 3))

        let recovery = app.buttons[ID.recoveryRoutine]
        XCTAssertTrue(recovery.waitForExistence(timeout: 3))
        recovery.tap()
        XCTAssertTrue(app.navigationBars["Recovery Day"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[ID.routineSelectToday].isEnabled)
        XCTAssertTrue(app.buttons[ID.routineAskPlanner].exists)
    }

    func testLibraryUsualWeekSupportsNoRoutineAssignment() throws {
        launch(fixture: .frozenRuntime)
        openTab("Library")

        let usualWeek = app.buttons["Usual Week"]
        XCTAssertTrue(usualWeek.waitForExistence(timeout: 5))
        usualWeek.tap()
        XCTAssertTrue(app.navigationBars["Usual Week"].waitForExistence(timeout: 3))

        let monday = app.buttons[ID.usualWeekMonday]
        XCTAssertTrue(monday.waitForExistence(timeout: 3))
        monday.tap()
        XCTAssertTrue(app.buttons["No Routine"].waitForExistence(timeout: 2))
        app.buttons["No Routine"].tap()

        XCTAssertTrue(waitForLabelContaining("No Routine", of: monday))
    }

    func testLibraryAppearanceUpdatesGlobalAccent() throws {
        launch(fixture: .frozenRuntime)
        openTab("Library")

        let more = app.buttons[ID.libraryMore]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(app.buttons["Appearance"].waitForExistence(timeout: 2))
        app.buttons["Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))

        let sunrise = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Sunrise")
        ).firstMatch
        XCTAssertTrue(sunrise.waitForExistence(timeout: 3))
        sunrise.tap()
        XCTAssertTrue(waitUntilSelected(sunrise))
        XCTAssertTrue(app.staticTexts["Sunrise"].exists)
    }

    func testSuggestionsExposePendingAcceptedAndRejectedStates() throws {
        launch(fixture: .suggestionsPending)
        openTab("Library")

        let suggestions = app.buttons[ID.librarySuggestions]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5))
        suggestions.tap()
        XCTAssertTrue(element(id: ID.suggestionsInbox).waitForExistence(timeout: 3))

        let daily = app.buttons[ID.dailySuggestion]
        XCTAssertTrue(daily.waitForExistence(timeout: 3))
        daily.tap()
        let accept = app.buttons[ID.suggestionAccept]
        XCTAssertTrue(accept.waitForExistence(timeout: 3))
        accept.tap()
        XCTAssertTrue(app.staticTexts["Accepted"].waitForExistence(timeout: 3))

        app.navigationBars.buttons["Suggestions"].tap()
        let improvement = app.buttons[ID.improvementSuggestion]
        XCTAssertTrue(improvement.waitForExistence(timeout: 3))
        improvement.tap()
        let reject = app.buttons[ID.suggestionReject]
        XCTAssertTrue(reject.waitForExistence(timeout: 3))
        reject.tap()
        XCTAssertTrue(app.staticTexts["Rejected"].waitForExistence(timeout: 3))
    }

    func testPlannerLaunchFixturesCoverAllConnectionStates() throws {
        let states: [(Fixture, String)] = [
            (.plannerDisconnected, "Planner Not Connected"),
            (.plannerConnected, "Planner Connected"),
            (.plannerUnavailable, "Planner Unavailable"),
            (.plannerNeedsAttention, "Planner Needs Attention")
        ]

        for (fixture, title) in states {
            launch(fixture: fixture)
            openTab("Library")
            let planner = app.buttons[ID.libraryPlanner]
            XCTAssertTrue(planner.waitForExistence(timeout: 5), "Missing Planner entry for \(fixture.rawValue)")
            planner.tap()
            XCTAssertTrue(element(id: ID.plannerScreen).waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts[title].exists, "Missing \(title) state")
        }
    }

    func testNoRoutineIsValidInNowTodayAndLibrary() throws {
        launch(fixture: .noRoutine)

        XCTAssertTrue(app.staticTexts["No Routine Today"].waitForExistence(timeout: 5))
        openTab("Today")
        XCTAssertTrue(app.buttons[ID.todayCurrentRoutine].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Routine Selected"].exists)

        openTab("Now")
        app.buttons["Choose Routine"].tap()
        XCTAssertTrue(app.navigationBars["All Routines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[ID.workdayRoutine].exists)
        XCTAssertTrue(app.buttons[ID.recoveryRoutine].exists)
    }

    func testLoadErrorNeverFallsBackToStarterOrSampleData() throws {
        launch(fixture: .loadError)

        XCTAssertTrue(app.staticTexts["Unable to Open Your Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertFalse(app.tabBars.buttons["Now"].exists)
        XCTAssertFalse(element(id: ID.firstRun).exists)
    }

    func testSemanticIdentifiersSurviveLargeDynamicType() throws {
        launch(
            fixture: .firstRun,
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        )

        XCTAssertTrue(element(id: ID.firstRun).waitForExistence(timeout: 5))
        let starter = app.buttons[ID.activationStarter]
        XCTAssertTrue(starter.exists)
        XCTAssertTrue(waitUntilHittable(starter))
        starter.tap()
        XCTAssertTrue(revealByScrolling(app.buttons[ID.activationStart]))
    }

    @discardableResult
    private func launch(
        fixture: Fixture,
        reset: Bool = true,
        route: String? = nil,
        simulationMinute: Int = 816,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        if app?.state != .notRunning {
            app?.terminate()
        }

        let application = XCUIApplication()
        application.launchEnvironment["SAMOYED_UI_TEST_FIXTURE"] = fixture.rawValue
        application.launchEnvironment["SAMOYED_UI_TEST_RESET"] = reset ? "1" : "0"
        application.launchEnvironment["SAMOYED_SIMULATION_MINUTE"] = String(simulationMinute)
        if let route {
            application.launchEnvironment["SAMOYED_UI_TEST_ROUTE"] = route
        }
        application.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        application.launchArguments += extraArguments
        app = application
        application.launch()
        return application
    }

    private func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing \(title) tab")
        tab.tap()
    }

    private func element(id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        wait(for: NSPredicate(format: "hittable == true"), element: element, timeout: timeout)
    }

    private func revealByScrolling(
        _ element: XCUIElement,
        attempts: Int = 4
    ) -> Bool {
        if element.waitForExistence(timeout: 1) { return true }

        for _ in 0..<attempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) { return true }
        }

        return false
    }

    private func waitUntilEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        wait(for: NSPredicate(format: "enabled == true"), element: element, timeout: timeout)
    }

    private func waitUntilSelected(
        _ element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        wait(for: NSPredicate(format: "selected == true"), element: element, timeout: timeout)
    }

    private func waitForValue(
        _ value: String,
        of element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        wait(for: NSPredicate(format: "value == %@", value), element: element, timeout: timeout)
    }

    private func waitForLabelContaining(
        _ value: String,
        of element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        wait(for: NSPredicate(format: "label CONTAINS %@", value), element: element, timeout: timeout)
    }

    private func wait(
        for predicate: NSPredicate,
        element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private var inlineImportRoute: String {
        let yaml = """
        version: 1
        kind: day_blocks
        source_date: 2026-08-14
        blocks:
          - title: Focus
            start: "09:00"
            end: "12:00"
            note: Protect one calm outcome.
            tasks:
              - title: Ship the smallest useful slice
          - title: Lunch
            start: "12:00"
            end: "13:00"
        """
        let payload = Data(yaml.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "samoyed"
        components.host = "import-routine"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "payload", value: payload),
            URLQueryItem(name: "title", value: "Imported Focus"),
            URLQueryItem(name: "source", value: "app")
        ]
        return components.url!.absoluteString
    }
}

private enum Fixture: String {
    case firstRun = "first-run"
    case frozenRuntime = "frozen-runtime"
    case feedbackValidation = "feedback-validation"
    case suggestionsPending = "suggestions-pending"
    case plannerDisconnected = "planner-disconnected"
    case plannerConnected = "planner-connected"
    case plannerUnavailable = "planner-unavailable"
    case plannerNeedsAttention = "planner-needs-attention"
    case noRoutine = "no-routine"
    case loadError = "load-error"
}

private enum ID {
    static let firstRun = "first-run"
    static let activationStarter = "activation-starter"
    static let activationStart = "activation-start"
    static let nowFeedback = "now-feedback"
    static let feedbackSave = "feedback-save"
    static let feedbackDone = "feedback-done"
    static let feedbackGood = "feedback-sentiment-good"
    static let blockFeedback = "block-details-feedback"
    static let blockDone = "block-details-done"
    static let todayCurrentRoutine = "today-current-routine"
    static let todayNoRoutine = "today-no-routine"
    static let libraryCurrentRoutine = "library-current-routine"
    static let libraryMore = "library-more"
    static let librarySuggestions = "library-suggestions"
    static let libraryPlanner = "library-planner"
    static let routineSelectToday = "routine-select-today"
    static let routineAskPlanner = "routine-ask-planner"
    static let usualWeekMonday = "usual-week-2"
    static let suggestionsInbox = "suggestions-inbox"
    static let suggestionAccept = "suggestion-accept"
    static let suggestionReject = "suggestion-reject"
    static let plannerScreen = "planner-screen"
    static let workdayRoutine = "routine-available-10000000-0000-0000-0000-000000000001"
    static let recoveryRoutine = "routine-available-10000000-0000-0000-0000-000000000002"
    static let dailySuggestion = "suggestion-20000000-0000-0000-0000-000000000001"
    static let improvementSuggestion = "suggestion-20000000-0000-0000-0000-000000000002"
}
