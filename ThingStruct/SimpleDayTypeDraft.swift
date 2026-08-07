import Foundation

struct SimpleDayTypeBlockDraft: Identifiable, Equatable {
    var id: UUID
    var title: String
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var taskBlueprints: [TaskBlueprint]

    init(
        id: UUID = UUID(),
        title: String,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        taskBlueprints: [TaskBlueprint] = []
    ) {
        self.id = id
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.taskBlueprints = taskBlueprints
    }

    var blockTemplate: BlockTemplate {
        BlockTemplate(
            id: id,
            layerIndex: 0,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            taskBlueprints: taskBlueprints
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .enumerated()
                .map { index, blueprint in
                    var copy = blueprint
                    copy.title = blueprint.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    copy.order = index
                    return copy
                },
            timing: .absolute(
                startMinuteOfDay: startMinuteOfDay,
                requestedEndMinuteOfDay: endMinuteOfDay
            )
        )
    }
}

struct SimpleDayTypeDraft: Equatable {
    var templateID: UUID?
    var title: String
    var assignedWeekdays: Set<Weekday>
    var blocks: [SimpleDayTypeBlockDraft]

    static var workdayStarter: SimpleDayTypeDraft {
        SimpleDayTypeDraft(
            templateID: nil,
            title: "Workday",
            assignedWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            blocks: [
                SimpleDayTypeBlockDraft(
                    title: "Morning",
                    startMinuteOfDay: 8 * 60,
                    endMinuteOfDay: 12 * 60,
                    taskBlueprints: [TaskBlueprint(title: "Plan priorities")]
                ),
                SimpleDayTypeBlockDraft(
                    title: "Afternoon",
                    startMinuteOfDay: 13 * 60,
                    endMinuteOfDay: 18 * 60,
                    taskBlueprints: [TaskBlueprint(title: "Review progress")]
                ),
                SimpleDayTypeBlockDraft(
                    title: "Evening",
                    startMinuteOfDay: 18 * 60,
                    endMinuteOfDay: 22 * 60,
                    taskBlueprints: [TaskBlueprint(title: "Prepare tomorrow")]
                )
            ]
        )
    }

    static var newDayType: SimpleDayTypeDraft {
        SimpleDayTypeDraft(
            templateID: nil,
            title: "New Day Type",
            assignedWeekdays: [],
            blocks: [
                SimpleDayTypeBlockDraft(
                    title: "Main Block",
                    startMinuteOfDay: 9 * 60,
                    endMinuteOfDay: 17 * 60
                )
            ]
        )
    }

    init(
        templateID: UUID?,
        title: String,
        assignedWeekdays: Set<Weekday>,
        blocks: [SimpleDayTypeBlockDraft]
    ) {
        self.templateID = templateID
        self.title = title
        self.assignedWeekdays = assignedWeekdays
        self.blocks = blocks
    }

    init?(template: SavedDayTemplate, assignedWeekdays: Set<Weekday>) {
        guard template.isSimpleDayType else { return nil }
        templateID = template.id
        title = template.title
        self.assignedWeekdays = assignedWeekdays
        blocks = template.blocks.compactMap { block in
            guard case let .absolute(start, requestedEnd) = block.timing, let end = requestedEnd else {
                return nil
            }
            return SimpleDayTypeBlockDraft(
                id: block.id,
                title: block.title,
                startMinuteOfDay: start,
                endMinuteOfDay: end,
                taskBlueprints: block.taskBlueprints
            )
        }
    }

    func makeNewTemplate(createdAt: Date = .now) throws -> SavedDayTemplate {
        try TemplateEngine.makeSimpleSavedTemplate(
            title: title,
            blocks: blocks.map(\.blockTemplate),
            createdAt: createdAt
        )
    }
}

extension SavedDayTemplate {
    var isSimpleDayType: Bool {
        blocks.allSatisfy { block in
            guard
                block.layerIndex == 0,
                block.parentTemplateBlockID == nil,
                block.reminders.isEmpty
            else {
                return false
            }
            if case .absolute(_, .some) = block.timing {
                return true
            }
            return false
        }
    }
}
