import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct ThingStructCurrentBlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThingStructCurrentBlockActivityAttributes.self) { context in
            ThingStructLiveActivityLockScreenView(context: context)
                .widgetURL(context.tapURL)
                .activityBackgroundTint(context.state.activityBackground)
                .activitySystemActionForegroundColor(context.state.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        ThingStructLiveActivityMark(accent: context.state.accent, compact: true)

                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.remainingLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.accent)
                        .contentTransition(.numericText())
                        .padding(.trailing, 4)
                        .padding(.top, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ThingStructLiveActivityBody(
                        state: context.state,
                        noteLineLimit: context.state.displaySourceBlockTitle == nil ? 2 : 3,
                        compact: true
                    )
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.compactIconName)
                    .foregroundStyle(context.state.accent)
            } compactTrailing: {
                Text(context.state.compactTrailingText)
                    .font(.caption2.weight(.semibold))
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: context.state.minimalIconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(context.state.accent)
            }
            .widgetURL(context.tapURL)
            .keylineTint(context.state.accent)
        }
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ThingStructCurrentBlockActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ThingStructLiveActivityMark(accent: context.state.accent)

                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(context.state.remainingLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.accent)
                    .contentTransition(.numericText())
            }

            ThingStructLiveActivityBody(
                state: context.state,
                noteLineLimit: 2,
                compact: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityBody: View {
    let state: ThingStructCurrentBlockActivityAttributes.ContentState
    let noteLineLimit: Int
    let compact: Bool

    var body: some View {
        if state.isCaughtUp {
            caughtUpContent
        } else {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                if let sourceTitle = state.displaySourceBlockTitle {
                    Text("FROM \(sourceTitle.uppercased())")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state.accent)
                        .lineLimit(1)
                }

                if let note = state.displayNote {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(state.accent)
                            .padding(.top, 2)

                        Text(note)
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(noteLineLimit)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                }

                if !state.actionableTasks.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(state.actionableTasks.prefix(2)) { item in
                            ThingStructLiveActivityTaskToggle(
                                item: item,
                                accent: state.accent,
                                compact: compact
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var caughtUpContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("All caught up")
                    .font(.subheadline.weight(.semibold))

                Text("Nothing needs your attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 17.0, *)
private struct ThingStructLiveActivityTaskToggle: View {
    let item: ThingStructCurrentBlockActivityAttributes.ActionItem
    let accent: Color
    let compact: Bool

    var body: some View {
        Toggle(
            isOn: false,
            intent: CompleteLiveActivityTaskIntent(
                dateISO: item.dateISO,
                blockID: item.blockID,
                taskID: item.taskID
            )
        ) {
            Label {
                Text(item.title)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } icon: {
                Image(systemName: "circle")
                    .imageScale(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .tint(accent)
        .padding(.horizontal, compact ? 8 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 30 : 36)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        .accessibilityLabel("Complete \(item.title)")
        .accessibilityHint("Marks this checklist item complete without opening ThingStruct")
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityMark: View {
    let accent: Color
    var compact = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
            .background(accent, in: Circle())
            .accessibilityHidden(true)
    }
}

@available(iOS 16.1, *)
private extension ActivityViewContext<ThingStructCurrentBlockActivityAttributes> {
    var tapURL: URL? {
        URL(string: state.tapURL)
    }
}

@available(iOS 16.1, *)
private extension ThingStructCurrentBlockActivityAttributes.ContentState {
    var isCaughtUp: Bool {
        remainingTaskCount == 0
    }

    var accent: Color {
        isCaughtUp ? .secondary : AppTintPreset.current.tintColor
    }

    var activityBackground: Color {
        isCaughtUp
            ? LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true).surface
            : LayerVisualStyle.forBlock(layerIndex: 1, isBlank: false).surface
    }

    var remainingLabel: String {
        isCaughtUp ? "Done" : "\(remainingTaskCount) left"
    }

    var compactIconName: String {
        isCaughtUp ? "checkmark.circle.fill" : "bolt.fill"
    }

    var minimalIconName: String {
        isCaughtUp ? "checkmark" : "bolt.fill"
    }

    var compactTrailingText: String {
        isCaughtUp ? "Done" : "\(min(remainingTaskCount, 9))"
    }
}

@available(iOS 16.1, *)
private let liveActivityPreviewAttributes = ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-08-12",
    currentBlockID: UUID().uuidString
)

@available(iOS 16.1, *)
private extension ThingStructCurrentBlockActivityAttributes.ContentState {
    static func preview(
        title: String,
        remainingTaskCount: Int,
        displayNote: String?,
        taskTitles: [String],
        displaySourceBlockTitle: String?,
        statusMessage: String?
    ) -> Self {
        ThingStructCurrentBlockActivityAttributes.ContentState(
            title: title,
            timeRangeText: "",
            remainingTaskCount: remainingTaskCount,
            tapURL: ThingStructSystemRoute.now(source: .liveActivity).url?.absoluteString ?? "thingstruct://now",
            displayNote: displayNote,
            actionableTasks: taskTitles.map { title in
                ThingStructCurrentBlockActivityAttributes.ActionItem(
                    dateISO: "2026-08-12",
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: title
                )
            },
            displaySourceBlockTitle: displaySourceBlockTitle,
            statusMessage: statusMessage
        )
    }

    static let previewTopLayer = preview(
        title: "Focus Sprint",
        remainingTaskCount: 2,
        displayNote: "Keep the review moving while decisions are fresh.",
        taskTitles: ["Ship surfaces", "Review states"],
        displaySourceBlockTitle: nil,
        statusMessage: nil
    )

    static let previewFallbackLayer = preview(
        title: "Launch Window",
        remainingTaskCount: 3,
        displayNote: "Use the remaining space to protect launch quality and handoff clarity.",
        taskTitles: ["Review progress", "Send launch notes"],
        displaySourceBlockTitle: "Afternoon",
        statusMessage: nil
    )

    static let previewCaughtUp = preview(
        title: "Morning",
        remainingTaskCount: 0,
        displayNote: nil,
        taskTitles: [],
        displaySourceBlockTitle: nil,
        statusMessage: "No incomplete tasks in this chain."
    )
}

#Preview("Live Activity Active", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewTopLayer
}

#Preview("Live Activity Fallback", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewFallbackLayer
}

#Preview("Live Activity Caught Up", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewCaughtUp
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewTopLayer
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewTopLayer
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewTopLayer
}
