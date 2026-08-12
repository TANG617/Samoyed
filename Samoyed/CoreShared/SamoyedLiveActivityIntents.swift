#if canImport(ActivityKit) && canImport(AppIntents) && canImport(WidgetKit) && !os(macOS)
import ActivityKit
import AppIntents
import Foundation
import WidgetKit

/// Runs inside the app process so a Live Activity interaction can persist the
/// task and publish a new ActivityKit content state without opening the app UI.
@available(iOS 17.0, *)
struct CompleteLiveActivityTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Live Activity Task"
    static let description = IntentDescription("Complete a checklist item shown in the Samoyed Live Activity.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Date ISO")
    var dateISO: String

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(dateISO: String, blockID: String, taskID: String) {
        self.dateISO = dateISO
        self.blockID = blockID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard
            let localDay = LocalDay(isoDateString: dateISO),
            let blockUUID = UUID(uuidString: blockID),
            let taskUUID = UUID(uuidString: taskID)
        else {
            return .result()
        }

        let repository = SamoyedDocumentRepository.appLive

        do {
            _ = try repository.completeTask(
                on: localDay,
                blockID: blockUUID,
                taskID: taskUUID
            )

            WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
            _ = try await SamoyedCurrentBlockLiveActivityController.sync(
                using: repository,
                at: .now
            )
        } catch {
            // Keep the interaction non-opening. A later app/widget refresh reads
            // the same shared store and reconciles the optimistic Toggle state.
            WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
        }

        return .result()
    }
}
#endif
