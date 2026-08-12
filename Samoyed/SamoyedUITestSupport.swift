#if DEBUG
import Foundation

@MainActor
enum SamoyedUITestSupport {
    private static let fixtureKey = "SAMOYED_UI_TEST_FIXTURE"
    private static let resetKey = "SAMOYED_UI_TEST_RESET"

    static func makeStoreIfRequested(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> SamoyedStore? {
        guard let fixture = processInfo.environment[fixtureKey] else { return nil }

        // The app-group container survives process relaunches and test-runner reinstall cycles.
        // A dedicated subdirectory keeps fixtures isolated from the real shared document.
        let root = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SamoyedSharedConfig.appGroupID
        ) ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let fileURL = root
            .appending(path: "SamoyedUITests", directoryHint: .isDirectory)
            .appending(path: "document.json")
        let repository = SamoyedDocumentRepository(fileURL: fileURL)

        if processInfo.environment[resetKey] == "1" {
            try? fileManager.removeItem(at: fileURL)
            prepareFixture(fixture, repository: repository, fileURL: fileURL)
        }

        return SamoyedStore(
            documentRepository: repository,
            validationLogger: ValidationEventLogger(enabled: false)
        )
    }

    private static func prepareFixture(
        _ fixture: String,
        repository: SamoyedDocumentRepository,
        fileURL: URL
    ) {
        switch fixture {
        case "empty":
            break

        case "active", "complex":
            if let document = try? SampleDataFactory.seededDocument(referenceDay: .today()) {
                try? repository.save(document)
            }

        case "open-time":
            let now = Date.now.minuteOfDay
            let beforeEnd = max(min(now - 30, 10 * 60), 60)
            let afterStart = min(max(now + 30, beforeEnd + 30), 22 * 60)
            let plan = DayPlan(
                date: .today(),
                blocks: [
                    TimeBlock(
                        layerIndex: 0,
                        title: "Earlier",
                        timing: .absolute(startMinuteOfDay: max(beforeEnd - 60, 0), requestedEndMinuteOfDay: beforeEnd)
                    ),
                    TimeBlock(
                        layerIndex: 0,
                        title: "Later",
                        timing: .absolute(startMinuteOfDay: afterStart, requestedEndMinuteOfDay: min(afterStart + 60, 24 * 60))
                    )
                ]
            )
            try? repository.save(SamoyedDocument(dayPlans: [plan]))

        case "all-done":
            let now = Date.now.minuteOfDay
            let start = max(now - 30, 0)
            let end = min(max(now + 30, start + 5), 24 * 60)
            let plan = DayPlan(
                date: .today(),
                blocks: [
                    TimeBlock(
                        layerIndex: 0,
                        title: "Finished",
                        tasks: [TaskItem(title: "Done", isCompleted: true, completedAt: .now)],
                        timing: .absolute(startMinuteOfDay: start, requestedEndMinuteOfDay: end)
                    )
                ]
            )
            try? repository.save(SamoyedDocument(dayPlans: [plan]))

        case "single-layer-days":
            let today = LocalDay.today()
            let tomorrow = today.adding(days: 1)

            func plan(for day: LocalDay) -> DayPlan {
                DayPlan(
                    date: day,
                    blocks: [
                        TimeBlock(
                            layerIndex: 0,
                            title: "Morning",
                            tasks: [TaskItem(title: "Plan the day")],
                            timing: .absolute(startMinuteOfDay: 420, requestedEndMinuteOfDay: 720)
                        ),
                        TimeBlock(
                            layerIndex: 0,
                            title: "Lunch",
                            timing: .absolute(startMinuteOfDay: 720, requestedEndMinuteOfDay: 780)
                        ),
                        TimeBlock(
                            layerIndex: 0,
                            title: "Afternoon",
                            tasks: [
                                TaskItem(title: "Review progress"),
                                TaskItem(title: "Wrap up", order: 1)
                            ],
                            timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
                        ),
                        TimeBlock(
                            layerIndex: 0,
                            title: "Evening",
                            timing: .absolute(startMinuteOfDay: 1080, requestedEndMinuteOfDay: 1320)
                        )
                    ]
                )
            }

            try? repository.save(
                SamoyedDocument(dayPlans: [plan(for: today), plan(for: tomorrow)])
            )

        case "elastic-timeline":
            let afternoonID = UUID()
            let plan = DayPlan(
                date: .today(),
                blocks: [
                    TimeBlock(
                        layerIndex: 0,
                        title: "Before",
                        timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 600)
                    ),
                    TimeBlock(
                        layerIndex: 0,
                        title: "Lunch",
                        timing: .absolute(startMinuteOfDay: 720, requestedEndMinuteOfDay: 780)
                    ),
                    TimeBlock(
                        id: afternoonID,
                        layerIndex: 0,
                        title: "Afternoon",
                        timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
                    ),
                    TimeBlock(
                        parentBlockID: afternoonID,
                        layerIndex: 1,
                        title: "Project Work",
                        timing: .relative(startOffsetMinutes: 15, requestedDurationMinutes: 150)
                    ),
                    TimeBlock(
                        layerIndex: 0,
                        title: "After",
                        timing: .absolute(startMinuteOfDay: 1080, requestedEndMinuteOfDay: 1440)
                    )
                ]
            )
            try? repository.save(SamoyedDocument(dayPlans: [plan]))

        case "load-error":
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? Data("not-json".utf8).write(to: fileURL, options: .atomic)

        default:
            break
        }
    }
}
#endif
