#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation

// Live Activity 的“属性”和“内容状态”需要是独立的可编码类型，
// 因为它们会被系统拿去在锁屏、Dynamic Island 等系统 UI 中展示。
// 这里和普通 SwiftUI View State 不同，它更像一个跨进程展示载荷。
@available(iOS 16.1, *)
struct SamoyedCurrentBlockActivityAttributes: ActivityAttributes {
    struct ActionItem: Codable, Hashable, Identifiable {
        var dateISO: String
        var blockID: String
        var taskID: String
        var title: String

        var id: String {
            taskID
        }
    }

    public struct ContentState: Codable, Hashable {
        var title: String
        var timeRangeText: String
        var remainingTaskCount: Int
        var tapURL: String
        var displayNote: String?
        var actionableTasks: [ActionItem]
        var displaySourceBlockTitle: String?
        var statusMessage: String?
    }

    var dateISO: String
    var currentBlockID: String
}

// 这个控制器统一管理当前 block 的 Live Activity 生命周期。
// 责任包括：
// - 根据 repository 生成快照
// - 决定应该启动、更新还是结束 activity
// - 保证同一时刻不会残留多份重复 activity
@available(iOS 16.1, *)
enum SamoyedLiveActivityStartOutcome: Equatable, Sendable {
    case startedOrUpdated
    case unavailable(SamoyedLiveActivityEligibility)

    var userMessage: String {
        switch self {
        case .startedOrUpdated:
            return "Started tracking the current block."
        case let .unavailable(reason):
            return reason.userMessage
        }
    }
}

@available(iOS 16.1, *)
enum SamoyedCurrentBlockLiveActivityController {
    static func start(
        using repository: SamoyedDocumentRepository = .appLive,
        at date: Date = .now
    ) async throws -> SamoyedLiveActivityStartOutcome {
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let snapshot = try repository.liveActivitySnapshot(at: date)
        let eligibility = SamoyedLiveActivityPolicy.eligibility(
            for: snapshot,
            activitiesEnabled: activitiesEnabled
        )

        guard eligibility == .eligible else {
            await endAll()
            return .unavailable(eligibility)
        }

        guard let payload = payload(from: snapshot, referenceDate: date) else {
            await endAll()
            return .unavailable(.noCurrentBlock)
        }

        if let existing = matchingActivity(for: payload) {
            await existing.update(payload.content)
            await endAll(excluding: existing.id)
            return .startedOrUpdated
        }

        await endAll()
        _ = try Activity.request(
            attributes: payload.attributes,
            content: payload.content,
            pushType: nil
        )
        return .startedOrUpdated
    }

    static func sync(
        using repository: SamoyedDocumentRepository = .appLive,
        at date: Date = .now
    ) async throws -> Bool {
        // Sync is update-only. Starting is always an explicit user action.
        guard !Activity<SamoyedCurrentBlockActivityAttributes>.activities.isEmpty else {
            return false
        }

        let snapshot = try repository.liveActivitySnapshot(at: date)
        let eligibility = SamoyedLiveActivityPolicy.eligibility(
            for: snapshot,
            activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled
        )
        guard eligibility == .eligible,
              let payload = payload(from: snapshot, referenceDate: date)
        else {
            await endAll()
            return false
        }

        guard let existing = matchingActivity(for: payload) else {
            // Attributes are immutable. A new block needs a new explicit start.
            await endAll()
            return false
        }

        await existing.update(payload.content)
        await endAll(excluding: existing.id)
        return true
    }

    static func endAll() async {
        await endAll(excluding: nil)
    }

    static func endAll(excluding activityID: String?) async {
        // `Activity.activities` 给出当前 app 仍活着的所有 activity 实例。
        for activity in Activity<SamoyedCurrentBlockActivityAttributes>.activities
        where activity.id != activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func payload(
        from snapshot: SamoyedSystemLiveActivitySnapshot,
        referenceDate: Date
    ) -> Payload? {
        // 只有在“存在非空白当前块，且还没结束，且能构造跳转 URL”时才值得展示。
        guard
            let currentBlock = snapshot.currentBlock,
            !currentBlock.isBlank,
            currentBlock.endMinuteOfDay > snapshot.minuteOfDay,
            let tapURL = snapshot.tapURL()
        else {
            return nil
        }

        // `staleDate` 告诉系统：这份内容在什么时候之后应该被视为过期。
        let staleDate = currentBlock.date.date(minuteOfDay: currentBlock.endMinuteOfDay) ?? referenceDate.addingTimeInterval(15 * 60)
        let attributes = SamoyedCurrentBlockActivityAttributes(
            dateISO: currentBlock.date.description,
            currentBlockID: currentBlock.blockID.uuidString
        )
        let content = ActivityContent(
            state: SamoyedCurrentBlockActivityAttributes.ContentState(
                title: currentBlock.title,
                timeRangeText: currentBlock.timeRangeText,
                remainingTaskCount: snapshot.remainingTaskCount,
                tapURL: tapURL.absoluteString,
                displayNote: snapshot.displayNote,
                actionableTasks: snapshot.displayTasks.map { task in
                    SamoyedCurrentBlockActivityAttributes.ActionItem(
                        dateISO: task.date.description,
                        blockID: task.blockID.uuidString,
                        taskID: task.taskID.uuidString,
                        title: task.title
                    )
                },
                displaySourceBlockTitle: snapshot.displaySourceBlockTitle,
                statusMessage: snapshot.statusMessage
            ),
            staleDate: staleDate
        )

        return Payload(attributes: attributes, content: content)
    }

    private static func matchingActivity(
        for payload: Payload
    ) -> Activity<SamoyedCurrentBlockActivityAttributes>? {
        Activity<SamoyedCurrentBlockActivityAttributes>.activities.first {
            $0.attributes.currentBlockID == payload.attributes.currentBlockID &&
                $0.attributes.dateISO == payload.attributes.dateISO
        }
    }
}

@available(iOS 16.1, *)
private struct Payload {
    // 只是一个内部打包结构，避免函数返回超长元组。
    let attributes: SamoyedCurrentBlockActivityAttributes
    let content: ActivityContent<SamoyedCurrentBlockActivityAttributes.ContentState>
}
#endif
