import XCTest
@testable import SamoyedCore

final class InteractionRegressionTests: XCTestCase {
    func testNowChecklistGroupsAdjacentTasksAtTheSameLayerIntoOneSurface() {
        let blockID = UUID()
        let first = TaskItem(title: "First")
        let second = TaskItem(title: "Second", order: 1)
        let section = NowTaskSection(
            id: blockID,
            title: "Project Work",
            layerIndex: 1,
            startMinuteOfDay: 795,
            endMinuteOfDay: 945,
            tasks: [first, second],
            isCurrent: true,
            isTaskSource: true,
            isComplete: false
        )

        let groups = NowChecklistDisplayBuilder.groups(
            from: NowChecklistDisplayBuilder.sortedItems(from: [section])
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].layerIndex, 1)
        XCTAssertFalse(groups[0].isCompleted)
        XCTAssertEqual(groups[0].items.map(\.task.id), [first.id, second.id])
    }

    func testNowChecklistMovesCompletedItemsToASeparateFinalGroup() {
        let section = NowTaskSection(
            id: UUID(),
            title: "Project Work",
            layerIndex: 1,
            startMinuteOfDay: 795,
            endMinuteOfDay: 945,
            tasks: [
                TaskItem(title: "Done", isCompleted: true),
                TaskItem(title: "Remaining", order: 1)
            ],
            isCurrent: true,
            isTaskSource: true,
            isComplete: false
        )

        let groups = NowChecklistDisplayBuilder.groups(
            from: NowChecklistDisplayBuilder.sortedItems(from: [section])
        )

        XCTAssertEqual(groups.map(\.isCompleted), [false, true])
        XCTAssertEqual(groups.flatMap(\.items).map(\.task.title), ["Remaining", "Done"])
    }

    func testTimelineSingleLayerBlockResolvesToItsTimeInsteadOfCanvasTop() {
        let blockID = UUID()
        let block = TimelineBlockItem(
            id: blockID,
            parentBlockID: nil,
            title: "Afternoon",
            note: nil,
            startMinuteOfDay: 780,
            endMinuteOfDay: 1080,
            layerIndex: 0,
            isBlank: false,
            incompleteTaskCount: 0
        )

        XCTAssertEqual(
            TodayTimelineScrollTargetResolver.targetMinute(
                for: blockID,
                in: [block],
                fallbackMinute: 816
            ),
            816
        )
        XCTAssertEqual(
            TodayTimelineScrollTargetResolver.targetMinute(
                for: blockID,
                in: [block],
                fallbackMinute: 300
            ),
            780
        )
        XCTAssertEqual(
            TodayTimelineScrollTargetResolver.anchorHour(
                for: 816,
                startHour: 6,
                endHour: 23
            ),
            13
        )
    }

    func testElasticTimelineUsesOneTruthfulMappingForFigmaCurrentTimeState() {
        let afternoonID = UUID()
        let projectWorkID = UUID()
        let blocks = [
            TimelineBlockItem(
                id: UUID(),
                parentBlockID: nil,
                title: "Lunch",
                note: nil,
                startMinuteOfDay: 720,
                endMinuteOfDay: 780,
                layerIndex: 0,
                isBlank: false,
                incompleteTaskCount: 0
            ),
            TimelineBlockItem(
                id: afternoonID,
                parentBlockID: nil,
                title: "Afternoon",
                note: nil,
                startMinuteOfDay: 780,
                endMinuteOfDay: 1080,
                layerIndex: 0,
                isBlank: false,
                incompleteTaskCount: 0
            ),
            TimelineBlockItem(
                id: projectWorkID,
                parentBlockID: afternoonID,
                title: "Project Work",
                note: nil,
                startMinuteOfDay: 795,
                endMinuteOfDay: 945,
                layerIndex: 1,
                isBlank: false,
                incompleteTaskCount: 0
            )
        ]
        let scale = TimelineElasticTimeScale(
            blocks: blocks,
            openSlots: [
                TodayOpenSlotItem(
                    id: UUID(),
                    startMinuteOfDay: 600,
                    endMinuteOfDay: 720
                )
            ],
            currentMinute: 816,
            topInset: 0,
            bottomInset: 0
        )

        XCTAssertEqual(scale.distance(from: 600, to: 660), 56, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 660, to: 720), 56, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 720, to: 780), 64, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 780, to: 795), 68, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 795, to: 816), 82, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 816, to: 840), 56, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 840, to: 900), 56, accuracy: 0.001)
        XCTAssertEqual(scale.distance(from: 780, to: 840), 206, accuracy: 0.001)

        let orderedMinutes = [600, 660, 720, 780, 795, 816, 840, 900]
        let positions = orderedMinutes.map(scale.yPosition(for:))
        XCTAssertEqual(positions, positions.sorted())
    }

    func testLiveActivityRequiresAuthorizationAndAnActiveNonblankBlock() {
        let day = LocalDay(year: 2026, month: 8, day: 12)
        let activeBlock = SamoyedSystemBlockReference(
            date: day,
            blockID: UUID(),
            title: "Project Work",
            layerIndex: 1,
            startMinuteOfDay: 795,
            endMinuteOfDay: 945,
            timeRangeText: "13:15 - 15:45",
            isBlank: false,
            isCurrent: true,
            remainingTaskCount: 2
        )
        let eligibleSnapshot = liveActivitySnapshot(
            day: day,
            minuteOfDay: 816,
            currentBlock: activeBlock
        )

        XCTAssertEqual(
            SamoyedLiveActivityPolicy.eligibility(
                for: eligibleSnapshot,
                activitiesEnabled: true
            ),
            .eligible
        )
        XCTAssertEqual(
            SamoyedLiveActivityPolicy.eligibility(
                for: eligibleSnapshot,
                activitiesEnabled: false
            ),
            .activitiesDisabled
        )
        XCTAssertEqual(
            SamoyedLiveActivityPolicy.eligibility(
                for: liveActivitySnapshot(day: day, minuteOfDay: 816, currentBlock: nil),
                activitiesEnabled: true
            ),
            .noCurrentBlock
        )

        var blankBlock = activeBlock
        blankBlock = SamoyedSystemBlockReference(
            date: blankBlock.date,
            blockID: blankBlock.blockID,
            title: "Open Time",
            layerIndex: blankBlock.layerIndex,
            startMinuteOfDay: blankBlock.startMinuteOfDay,
            endMinuteOfDay: blankBlock.endMinuteOfDay,
            timeRangeText: blankBlock.timeRangeText,
            isBlank: true,
            isCurrent: true,
            remainingTaskCount: 0
        )
        XCTAssertEqual(
            SamoyedLiveActivityPolicy.eligibility(
                for: liveActivitySnapshot(day: day, minuteOfDay: 816, currentBlock: blankBlock),
                activitiesEnabled: true
            ),
            .blankCurrentBlock
        )
        XCTAssertEqual(
            SamoyedLiveActivityPolicy.eligibility(
                for: liveActivitySnapshot(day: day, minuteOfDay: 945, currentBlock: activeBlock),
                activitiesEnabled: true
            ),
            .currentBlockEnded
        )
    }

    func testWidgetCompletionActionIsIdempotentAcrossRepeatedSystemInvocations() throws {
        let day = LocalDay(year: 2026, month: 8, day: 12)
        let blockID = UUID()
        let taskID = UUID()
        let block = TimeBlock(
            id: blockID,
            layerIndex: 0,
            title: "Project Work",
            tasks: [TaskItem(id: taskID, title: "Ship milestone")],
            timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "SamoyedTests")
            .appending(path: "\(UUID().uuidString).json")
        let repository = SamoyedDocumentRepository(fileURL: fileURL)
        try repository.save(SamoyedDocument(dayPlans: [DayPlan(date: day, blocks: [block])]))
        let completedAt = try XCTUnwrap(day.date(minuteOfDay: 816))

        XCTAssertTrue(
            try SamoyedWidgetTaskAction.setCompletion(
                on: day,
                blockID: blockID,
                taskID: taskID,
                isCompleted: true,
                completedAt: completedAt,
                repository: repository
            )
        )
        XCTAssertFalse(
            try SamoyedWidgetTaskAction.setCompletion(
                on: day,
                blockID: blockID,
                taskID: taskID,
                isCompleted: true,
                completedAt: completedAt.addingTimeInterval(30),
                repository: repository
            )
        )

        let savedTask = try XCTUnwrap(
            repository.load()?.dayPlan(for: day)?.blocks
                .first(where: { $0.id == blockID })?.tasks
                .first(where: { $0.id == taskID })
        )
        XCTAssertTrue(savedTask.isCompleted)
        XCTAssertEqual(savedTask.completedAt, completedAt)
    }

    private func liveActivitySnapshot(
        day: LocalDay,
        minuteOfDay: Int,
        currentBlock: SamoyedSystemBlockReference?
    ) -> SamoyedSystemLiveActivitySnapshot {
        SamoyedSystemLiveActivitySnapshot(
            date: day,
            minuteOfDay: minuteOfDay,
            currentBlock: currentBlock,
            displayBlock: currentBlock,
            displayTasks: [],
            displayNote: nil,
            displaySourceBlockTitle: nil,
            remainingTaskCount: currentBlock?.remainingTaskCount ?? 0,
            statusMessage: currentBlock == nil ? "Choose today’s routine" : nil
        )
    }
}
