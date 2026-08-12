import AppIntents
import SwiftUI
import WidgetKit

// 这是 Widget Extension 的程序入口。
// 与主 app 的 `@main App` 类似，这里告诉系统：
// “这个扩展里一共提供哪些 Widget / Live Activity / Control Widget”。
@main
struct SamoyedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // 普通主屏 Widget。
        SamoyedNowWidget()

        if #available(iOS 16.1, *) {
            // 锁屏 / Dynamic Island 的 Live Activity 入口。
            SamoyedCurrentBlockLiveActivity()
        }

        if #available(iOS 18.0, *) {
            // iOS 18 的 Control Widget，出现在控制中心等系统表面。
            SamoyedOpenNowControl()
            SamoyedCompleteCurrentTaskControl()
            SamoyedOpenCurrentBlockControl()
            SamoyedStartLiveActivityControl()
        }
    }
}

// Control Widget / Widget 内部使用的 intent 错误类型。
private enum SamoyedControlIntentError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "Unable to build the requested Samoyed route."
        }
    }
}

// 由 widget 中的任务按钮触发，执行“切换任务完成状态”。
// 这类 intent 默认不会暴露给用户搜索或配置，所以 `isDiscoverable = false`。
struct ToggleTaskCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Task Completion"
    static let description = IntentDescription("Toggle a task directly from the Samoyed widget.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Date ISO")
    var dateISO: String

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Task ID")
    var taskID: String

    // AppIntents 需要一个无参 init 供系统解码参数时使用。
    init() {}

    init(dateISO: String, blockID: String, taskID: String) {
        self.dateISO = dateISO
        self.blockID = blockID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        // Widget/Intent 经常通过字符串参数跨进程传递上下文，
        // 所以执行前先把字符串还原成业务层需要的强类型。
        guard
            let localDay = LocalDay(isoDateString: dateISO),
            let blockUUID = UUID(uuidString: blockID),
            let taskUUID = UUID(uuidString: taskID)
        else {
            return .result()
        }

        let repository = SamoyedDocumentRepository.widgetLive
        _ = try repository.toggleTask(
            on: localDay,
            blockID: blockUUID,
            taskID: taskUUID
        )
        WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
        return .result()
    }
}

// 以下几个 intent 主要给 iOS 18 Control Widget 使用。
// 它们和 App Shortcuts 一样，本质上都是“系统入口 -> 内部命令”的翻译层。
struct OpenNowControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Now"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = SamoyedSystemRoute.now(source: .control).url else {
            throw SamoyedControlIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenCurrentBlockControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Current Block"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        // 如果能精确定位到当前 block，就直接打开它；
        // 否则退化到打开 Now 页面。
        let executor = SamoyedSystemActionExecutor(repository: .widgetLive)
        let url = try executor.openCurrentBlockURL(at: .now, source: .control)
            ?? SamoyedSystemRoute.now(source: .control).url

        guard let url else {
            throw SamoyedControlIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct CompleteCurrentTaskControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Current Task"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let executor = SamoyedSystemActionExecutor(repository: .widgetLive)
        _ = try executor.completeCurrentTask(at: .now)
        WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)

        if #available(iOS 16.1, *) {
            _ = try await SamoyedCurrentBlockLiveActivityController.sync(
                using: .widgetLive,
                at: .now
            )
        }

        return .result()
    }
}

struct StartCurrentBlockLiveActivityControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Activity"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }

        _ = try await SamoyedCurrentBlockLiveActivityController.start(
            using: .widgetLive,
            at: .now
        )
        WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
        return .result()
    }
}

@available(iOS 18.0, *)
struct SamoyedOpenNowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // `StaticControlConfiguration` 可以理解成“一个按钮型系统控件”的声明。
        StaticControlConfiguration(kind: SamoyedSharedConfig.openNowControlKind) {
            ControlWidgetButton(action: OpenNowControlIntent()) {
                Label("Now", systemImage: "bolt.circle")
            }
        }
        .displayName("Open Now")
        .description("Jump straight into the Now screen.")
    }
}

@available(iOS 18.0, *)
struct SamoyedCompleteCurrentTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SamoyedSharedConfig.completeCurrentTaskControlKind) {
            ControlWidgetButton(action: CompleteCurrentTaskControlIntent()) {
                Label("Complete Current Task", systemImage: "checkmark.circle")
            }
        }
        .displayName("Complete Task")
        .description("Check off the highest-priority current task.")
    }
}

@available(iOS 18.0, *)
struct SamoyedOpenCurrentBlockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SamoyedSharedConfig.openCurrentBlockControlKind) {
            ControlWidgetButton(action: OpenCurrentBlockControlIntent()) {
                Label("Open Current Block", systemImage: "scope")
            }
        }
        .displayName("Open Current Block")
        .description("Open Samoyed to the active block.")
    }
}

@available(iOS 18.0, *)
struct SamoyedStartLiveActivityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SamoyedSharedConfig.startLiveActivityControlKind) {
            ControlWidgetButton(action: StartCurrentBlockLiveActivityControlIntent()) {
                Label("Start Live Activity", systemImage: "waveform.path.ecg.rectangle")
            }
        }
        .displayName("Start Live Activity")
        .description("Start tracking the active block as a Live Activity.")
    }
}
