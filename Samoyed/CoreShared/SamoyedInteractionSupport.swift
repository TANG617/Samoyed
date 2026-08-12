import Foundation

struct NowChecklistDisplayItem: Identifiable, Equatable, Sendable {
    let blockID: UUID
    let layerIndex: Int
    let task: TaskItem

    var id: UUID { task.id }
}

struct NowChecklistDisplayGroup: Identifiable, Equatable, Sendable {
    let layerIndex: Int
    let isCompleted: Bool
    let items: [NowChecklistDisplayItem]

    var id: String {
        let state = isCompleted ? "completed" : "remaining"
        let firstID = items.first?.id.uuidString ?? "empty"
        return "layer-\(layerIndex)-\(state)-\(firstID)"
    }
}

enum NowChecklistDisplayBuilder {
    static func sortedItems(from sections: [NowTaskSection]) -> [NowChecklistDisplayItem] {
        sections
            .flatMap { section in
                section.tasks.map {
                    NowChecklistDisplayItem(
                        blockID: section.id,
                        layerIndex: section.layerIndex,
                        task: $0
                    )
                }
            }
            .sorted(by: taskSort)
    }

    static func groups(from items: [NowChecklistDisplayItem]) -> [NowChecklistDisplayGroup] {
        items.reduce(into: []) { groups, item in
            if
                let last = groups.last,
                last.layerIndex == item.layerIndex,
                last.isCompleted == item.task.isCompleted
            {
                groups[groups.count - 1] = NowChecklistDisplayGroup(
                    layerIndex: last.layerIndex,
                    isCompleted: last.isCompleted,
                    items: last.items + [item]
                )
            } else {
                groups.append(
                    NowChecklistDisplayGroup(
                        layerIndex: item.layerIndex,
                        isCompleted: item.task.isCompleted,
                        items: [item]
                    )
                )
            }
        }
    }

    private static func taskSort(
        _ lhs: NowChecklistDisplayItem,
        _ rhs: NowChecklistDisplayItem
    ) -> Bool {
        if lhs.task.isCompleted != rhs.task.isCompleted {
            return !lhs.task.isCompleted
        }
        if lhs.layerIndex != rhs.layerIndex {
            return lhs.layerIndex > rhs.layerIndex
        }
        if lhs.task.order != rhs.task.order {
            return lhs.task.order < rhs.task.order
        }
        return lhs.task.id.uuidString < rhs.task.id.uuidString
    }
}

struct TimelineElasticTimeScale: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let startMinute: Int
        let endMinute: Int
        let height: Double
    }

    let startHour: Int
    let endHour: Int
    let topInset: Double
    let bottomInset: Double
    let segments: [Segment]

    private static let quietHourHeight = 56.0
    private static let focusLeadInHourHeight = 64.0
    private static let nestedHeaderClearance = 68.0
    private static let currentCardBodyClearance = 82.0
    private static let focusTailHeight = 56.0

    init(
        blocks: [TimelineBlockItem],
        openSlots: [TodayOpenSlotItem],
        currentMinute: Int?,
        topInset: Double = 20,
        bottomInset: Double = 18
    ) {
        let ranges = blocks.map { ($0.startMinuteOfDay, $0.endMinuteOfDay) }
            + openSlots.map { ($0.startMinuteOfDay, $0.endMinuteOfDay) }
        let rangeMinutes = ranges.flatMap { [$0.0, $0.1] }
            + [currentMinute].compactMap { $0 }
        let earliest = rangeMinutes.min() ?? 7 * 60
        let latest = rangeMinutes.max() ?? 18 * 60

        startHour = max(0, earliest / 60 - 1)
        endHour = min(24, Int(ceil(Double(latest) / 60.0)) + 1)
        self.topInset = topInset
        self.bottomInset = bottomInset

        var builtSegments: [Segment] = []
        for hour in startHour ..< endHour {
            if let currentMinute, hour == currentMinute / 60 {
                builtSegments.append(
                    contentsOf: Self.focusSegments(
                        hour: hour,
                        currentMinute: currentMinute,
                        activeChain: Self.activeChain(in: blocks, at: currentMinute),
                        openSlots: openSlots
                    )
                )
            } else {
                let isFocusLeadInHour = currentMinute.map { hour == $0 / 60 - 1 } ?? false
                let height = isFocusLeadInHour
                    ? Self.focusLeadInHourHeight
                    : Self.quietHourHeight
                builtSegments.append(
                    Segment(
                        startMinute: hour * 60,
                        endMinute: (hour + 1) * 60,
                        height: height
                    )
                )
            }
        }
        segments = builtSegments
    }

    var hours: [Int] {
        Array(startHour ... endHour)
    }

    var canvasHeight: Double {
        topInset + segments.reduce(0) { $0 + $1.height } + bottomInset
    }

    func yPosition(for minute: Int) -> Double {
        let lowerBound = startHour * 60
        let upperBound = endHour * 60
        let clampedMinute = max(lowerBound, min(upperBound, minute))
        var position = topInset

        for segment in segments {
            if clampedMinute >= segment.endMinute {
                position += segment.height
                continue
            }
            guard clampedMinute > segment.startMinute else {
                return position
            }

            let duration = max(1, segment.endMinute - segment.startMinute)
            let progress = Double(clampedMinute - segment.startMinute) / Double(duration)
            return position + segment.height * progress
        }

        return position
    }

    func distance(from startMinute: Int, to endMinute: Int) -> Double {
        max(0, yPosition(for: endMinute) - yPosition(for: startMinute))
    }

    func hourHeight(for hour: Int) -> Double {
        distance(from: hour * 60, to: (hour + 1) * 60)
    }

    private static func focusSegments(
        hour: Int,
        currentMinute: Int,
        activeChain: [TimelineBlockItem],
        openSlots: [TodayOpenSlotItem]
    ) -> [Segment] {
        let hourStart = hour * 60
        let hourEnd = (hour + 1) * 60
        let now = max(hourStart, min(hourEnd, currentMinute))
        var result: [Segment] = []

        var activeStarts = activeChain
            .map(\.startMinuteOfDay)
            .filter { $0 >= hourStart && $0 <= now }

        if activeStarts.isEmpty,
           let openSlot = openSlots.first(where: {
               $0.startMinuteOfDay <= now && now < $0.endMinuteOfDay
           }) {
            activeStarts = [max(hourStart, openSlot.startMinuteOfDay)]
        }

        activeStarts = Array(Set(activeStarts)).sorted()
        var cursor = hourStart

        if let firstStart = activeStarts.first, firstStart > hourStart {
            if activeChain.contains(where: { $0.startMinuteOfDay < hourStart }) {
                result.append(
                    Segment(
                        startMinute: hourStart,
                        endMinute: firstStart,
                        height: nestedHeaderClearance
                    )
                )
            } else {
                let baselineHeight = quietHourHeight
                    * Double(firstStart - hourStart) / 60.0
                result.append(
                    Segment(
                        startMinute: hourStart,
                        endMinute: firstStart,
                        height: baselineHeight
                    )
                )
            }
            cursor = firstStart
        }

        for nestedStart in activeStarts where nestedStart > cursor {
            result.append(
                Segment(
                    startMinute: cursor,
                    endMinute: nestedStart,
                    height: nestedHeaderClearance
                )
            )
            cursor = nestedStart
        }

        if cursor < now {
            result.append(
                Segment(
                    startMinute: cursor,
                    endMinute: now,
                    height: currentCardBodyClearance
                )
            )
            cursor = now
        }

        if cursor < hourEnd {
            result.append(
                Segment(
                    startMinute: cursor,
                    endMinute: hourEnd,
                    height: focusTailHeight
                )
            )
        }

        if result.isEmpty {
            result.append(
                Segment(
                    startMinute: hourStart,
                    endMinute: hourEnd,
                    height: quietHourHeight
                )
            )
        }

        return result
    }

    private static func activeChain(
        in blocks: [TimelineBlockItem],
        at minute: Int
    ) -> [TimelineBlockItem] {
        let activeBlocks = blocks.filter {
            $0.startMinuteOfDay <= minute && minute < $0.endMinuteOfDay
        }
        guard let deepest = activeBlocks.max(by: { lhs, rhs in
            if lhs.layerIndex != rhs.layerIndex {
                return lhs.layerIndex < rhs.layerIndex
            }
            return lhs.startMinuteOfDay < rhs.startMinuteOfDay
        }) else {
            return []
        }

        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        var chain = [deepest]
        var parentID = deepest.parentBlockID
        while let id = parentID, let parent = byID[id] {
            chain.append(parent)
            parentID = parent.parentBlockID
        }
        return chain.reversed()
    }
}

enum TodayTimelineScrollTargetResolver {
    static func targetMinute(
        for blockID: UUID,
        in blocks: [TimelineBlockItem],
        fallbackMinute: Int
    ) -> Int {
        guard let block = blocks.first(where: { $0.id == blockID }) else {
            return fallbackMinute
        }

        if (block.startMinuteOfDay ..< block.endMinuteOfDay).contains(fallbackMinute) {
            return fallbackMinute
        }

        return block.startMinuteOfDay
    }

    static func anchorHour(
        for minute: Int,
        startHour: Int,
        endHour: Int
    ) -> Int {
        max(startHour, min(endHour, minute / 60))
    }
}

enum SamoyedLiveActivityEligibility: Equatable, Sendable {
    case eligible
    case activitiesDisabled
    case noCurrentBlock
    case blankCurrentBlock
    case currentBlockEnded

    var userMessage: String {
        switch self {
        case .eligible:
            return "Live Activity is ready."
        case .activitiesDisabled:
            return "Live Activities are disabled for Samoyed in Settings."
        case .noCurrentBlock:
            return "There isn’t an active block to track right now."
        case .blankCurrentBlock:
            return "Open Time doesn’t start a Live Activity."
        case .currentBlockEnded:
            return "The current block has already ended."
        }
    }
}

enum SamoyedLiveActivityPolicy {
    static func eligibility(
        for snapshot: SamoyedSystemLiveActivitySnapshot,
        activitiesEnabled: Bool
    ) -> SamoyedLiveActivityEligibility {
        guard activitiesEnabled else {
            return .activitiesDisabled
        }
        guard let currentBlock = snapshot.currentBlock else {
            return .noCurrentBlock
        }
        guard !currentBlock.isBlank else {
            return .blankCurrentBlock
        }
        guard currentBlock.endMinuteOfDay > snapshot.minuteOfDay else {
            return .currentBlockEnded
        }
        return .eligible
    }
}

enum SamoyedWidgetTaskAction {
    @discardableResult
    static func setCompletion(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        isCompleted: Bool,
        completedAt: Date = .now,
        repository: SamoyedDocumentRepository
    ) throws -> Bool {
        try repository.setTaskCompletion(
            on: date,
            blockID: blockID,
            taskID: taskID,
            isCompleted: isCompleted,
            completedAt: completedAt
        )
    }
}
