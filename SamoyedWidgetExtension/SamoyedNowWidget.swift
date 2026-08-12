import AppIntents
import SwiftUI
import WidgetKit

struct SamoyedNowWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SamoyedWidgetSnapshot
}

struct SamoyedNowWidgetProvider: TimelineProvider {
    private let repository = SamoyedDocumentRepository.widgetLive

    func placeholder(in context: Context) -> SamoyedNowWidgetEntry {
        SamoyedNowWidgetEntry(date: .now, snapshot: .placeholder())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SamoyedNowWidgetEntry) -> Void
    ) {
        completion(makeEntry(at: .now, isPreview: context.isPreview))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SamoyedNowWidgetEntry>) -> Void
    ) {
        let entry = makeEntry(at: .now, isPreview: context.isPreview)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    SamoyedWidgetSnapshotBuilder.nextRefreshDate(
                        for: entry.snapshot,
                        referenceDate: entry.date
                    )
                )
            )
        )
    }

    private func makeEntry(at date: Date, isPreview: Bool) -> SamoyedNowWidgetEntry {
        if isPreview {
            return SamoyedNowWidgetEntry(date: date, snapshot: .placeholder())
        }

        do {
            return SamoyedNowWidgetEntry(
                date: date,
                snapshot: try repository.widgetSnapshot(at: date, maxTaskCount: 3)
            )
        } catch {
            return SamoyedNowWidgetEntry(
                date: date,
                snapshot: SamoyedWidgetSnapshot(
                    date: LocalDay(date: date),
                    minuteOfDay: date.minuteOfDay,
                    requiresTemplateSelection: false,
                    currentBlockTitle: nil,
                    currentBlockTimeRangeText: nil,
                    currentBlockNote: nil,
                    blocks: [],
                    remainingTaskCount: 0,
                    tasks: [],
                    statusMessage: "Open Samoyed to finish setting up the widget."
                )
            )
        }
    }
}

struct SamoyedNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SamoyedSharedConfig.widgetKind,
            provider: SamoyedNowWidgetProvider()
        ) { entry in
            SamoyedNowWidgetEntryView(entry: entry)
                .widgetURL(entry.snapshot.destinationURL)
        }
        .configurationDisplayName("Samoyed Now")
        .description("See the current block and check off tasks without opening Samoyed.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular
        ])
        .contentMarginsDisabled()
    }
}

private struct SamoyedNowWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SamoyedNowWidgetEntry

    private var shownTasks: [SamoyedWidgetTaskItem] {
        Array(entry.snapshot.tasks.prefix(3))
    }

    private var shownBlocks: [SamoyedWidgetBlockItem] {
        Array(entry.snapshot.blocks.prefix(3))
    }

    private var currentBlock: SamoyedWidgetBlockItem? {
        entry.snapshot.blocks.first(where: \.isCurrent) ?? entry.snapshot.blocks.first
    }

    private var currentStyle: LayerVisualStyle {
        currentBlock.map(style(for:)) ?? LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true)
    }

    private var backgroundStyle: LayerVisualStyle {
        entry.snapshot.blocks.last.map(style(for:)) ?? currentStyle
    }

    private var isCaughtUp: Bool {
        !entry.snapshot.requiresTemplateSelection && entry.snapshot.remainingTaskCount == 0
    }

    private var remainingLabel: String {
        isCaughtUp ? "Done" : "\(entry.snapshot.remainingTaskCount) left"
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        case .accessoryInline:
            accessoryInlineLayout
        case .accessoryRectangular:
            accessoryRectangularLayout
        case .accessoryCircular:
            accessoryCircularLayout
        default:
            mediumLayout
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.snapshot.requiresTemplateSelection {
                setupCard(compact: true)
            } else if isCaughtUp {
                caughtUpCard(compact: true)
            } else {
                smallBlockStack
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.snapshot.requiresTemplateSelection {
                setupCard(compact: false)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    mediumCurrentBlock

                    if shownTasks.isEmpty {
                        caughtUpCard(compact: false)
                    } else {
                        VStack(spacing: 7) {
                            ForEach(shownTasks) { item in
                                taskToggle(item)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("NOW")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(currentStyle.accent)
                .tracking(0.4)

            Spacer(minLength: 8)

            if entry.snapshot.requiresTemplateSelection {
                Image(systemName: "exclamationmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(currentStyle.badgeForeground)
                    .frame(width: 22, height: 22)
                    .background(currentStyle.badgeBackground, in: Circle())
            } else if isCaughtUp {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.quaternary, in: Circle())
            } else {
                Text("\(entry.snapshot.remainingTaskCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(currentStyle.badgeForeground)
                    .frame(width: 22, height: 22)
                    .background(currentStyle.badgeBackground, in: Circle())
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now, \(entry.snapshot.requiresTemplateSelection ? "setup needed" : remainingLabel)")
    }

    private var smallBlockStack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(shownBlocks.enumerated().reversed()), id: \.element.id) { index, block in
                smallBlockCard(block, depth: index)
                    .offset(
                        x: CGFloat(index) * 3,
                        y: smallCardOffset(for: index)
                    )
                    .zIndex(Double(shownBlocks.count - index))
            }
        }
        .padding(.trailing, CGFloat(max(0, shownBlocks.count - 1)) * 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallCardOffset(for depth: Int) -> CGFloat {
        switch depth {
        case 0: return 0
        case 1: return 50
        default: return 74
        }
    }

    private func smallBlockCard(
        _ block: SamoyedWidgetBlockItem,
        depth: Int
    ) -> some View {
        let style = style(for: block)
        let isFront = depth == 0

        return VStack(alignment: .leading, spacing: 3) {
            Text(block.title)
                .font(isFront ? .footnote.weight(.semibold) : .caption2.weight(.semibold))
                .lineLimit(1)

            if isFront, let note = entry.snapshot.currentBlockNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, isFront ? 8 : 7)
        .frame(maxWidth: .infinity, minHeight: isFront ? 58 : 30, alignment: .topLeading)
        .background(
            (isFront ? style.strongSurface : style.surface),
            in: RoundedRectangle(cornerRadius: isFront ? 16 : 14, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if isFront {
                Capsule()
                    .fill(style.accent)
                    .frame(width: 3)
                    .padding(.vertical, 10)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var mediumCurrentBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.currentBlockTitle ?? "No current block")
                .font(.headline)
                .lineLimit(1)

            if let note = entry.snapshot.currentBlockNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(currentStyle.strongSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(currentStyle.accent)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }

    private func taskToggle(_ item: SamoyedWidgetTaskItem) -> some View {
        let style = style(for: item)

        return Toggle(
            isOn: item.isCompleted,
            intent: ToggleTaskCompletionIntent(
                dateISO: item.dateISO,
                blockID: item.blockID,
                taskID: item.taskID
            )
        ) {
            HStack(spacing: 7) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isCompleted ? .secondary : style.accent)

                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .tint(style.accent)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(
            item.isCompleted ? Color.secondary.opacity(0.09) : style.surface,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .invalidatableContent(true)
        .accessibilityLabel("\(item.isCompleted ? "Reopen" : "Complete") \(item.title)")
    }

    private func setupCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Choose today’s routine", systemImage: "calendar.badge.exclamationmark")
                .font(compact ? .footnote.weight(.semibold) : .headline)

            Text(entry.snapshot.statusMessage ?? "Open Samoyed to choose how today should be structured.")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 4 : 3)
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .background(currentStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func caughtUpCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("All caught up", systemImage: "checkmark.circle.fill")
                .font(compact ? .footnote.weight(.semibold) : .headline)
                .foregroundStyle(.secondary)

            Text("Nothing needs your attention.")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var accessoryInlineLayout: some View {
        Text(accessoryInlineText)
            .lineLimit(1)
            .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryInlineText: String {
        if entry.snapshot.requiresTemplateSelection {
            return "Choose today’s routine"
        }

        let title = entry.snapshot.currentBlockTitle ?? "Now"
        return isCaughtUp ? "\(title) · Done" : "\(title) · \(entry.snapshot.remainingTaskCount) left"
    }

    private var accessoryRectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((entry.snapshot.currentBlockTitle ?? "NOW").uppercased())
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            if entry.snapshot.requiresTemplateSelection {
                Text("Choose today’s routine")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if isCaughtUp {
                Text("All caught up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(entry.snapshot.remainingTaskCount) remaining")
                    .font(.caption2.weight(.semibold))

                Text(shownTasks.prefix(2).map(\.title).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryCircularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 1) {
                Image(systemName: isCaughtUp ? "checkmark" : "checklist")
                    .font(.caption2.weight(.semibold))

                Text(entry.snapshot.requiresTemplateSelection ? "!" : "\(min(entry.snapshot.remainingTaskCount, 9))")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [backgroundStyle.surface, currentStyle.surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func style(for block: SamoyedWidgetBlockItem) -> LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: block.isBlank)
    }

    private func style(for task: SamoyedWidgetTaskItem) -> LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: task.layerIndex, isBlank: task.isBlank)
    }
}

private extension SamoyedWidgetSnapshot {
    var destinationURL: URL? {
        if requiresTemplateSelection {
            return SamoyedSystemRoute.library(source: .widget).url
        }

        let currentBlockID = blocks.first(where: \.isCurrent)?.blockID ?? blocks.first?.blockID
        let currentTaskID = tasks.first(where: \.isCurrentBlock)?.taskID ?? tasks.first?.taskID

        if let currentBlockID, let blockID = UUID(uuidString: currentBlockID) {
            return SamoyedSystemRoute.today(
                date: date,
                blockID: blockID,
                taskID: currentTaskID.flatMap(UUID.init(uuidString:)),
                source: .widget
            ).url
        }

        return SamoyedSystemRoute.now(source: .widget).url
    }

    static var previewFocused: SamoyedWidgetSnapshot {
        let currentBlockID = UUID().uuidString
        let baseBlockID = UUID().uuidString

        return SamoyedWidgetSnapshot(
            date: LocalDay(year: 2026, month: 8, day: 12),
            minuteOfDay: 10 * 60,
            requiresTemplateSelection: false,
            currentBlockTitle: "Deep Work",
            currentBlockTimeRangeText: "09:00 - 11:00",
            currentBlockNote: "Finish the review while the decisions are fresh.",
            blocks: [
                SamoyedWidgetBlockItem(
                    blockID: currentBlockID,
                    title: "Deep Work",
                    layerIndex: 2,
                    timeRangeText: "09:00 - 11:00",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
                ),
                SamoyedWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Focus Work",
                    layerIndex: 1,
                    timeRangeText: "08:30 - 11:30",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                ),
                SamoyedWidgetBlockItem(
                    blockID: baseBlockID,
                    title: "Morning",
                    layerIndex: 0,
                    timeRangeText: "08:00 - 12:00",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                )
            ],
            remainingTaskCount: 3,
            tasks: [
                SamoyedWidgetTaskItem(
                    dateISO: "2026-08-12",
                    blockID: currentBlockID,
                    taskID: UUID().uuidString,
                    title: "Ship surfaces",
                    blockTitle: "Deep Work",
                    layerIndex: 2,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                ),
                SamoyedWidgetTaskItem(
                    dateISO: "2026-08-12",
                    blockID: currentBlockID,
                    taskID: UUID().uuidString,
                    title: "Review states",
                    blockTitle: "Deep Work",
                    layerIndex: 2,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                ),
                SamoyedWidgetTaskItem(
                    dateISO: "2026-08-12",
                    blockID: baseBlockID,
                    taskID: UUID().uuidString,
                    title: "Send launch notes",
                    blockTitle: "Morning",
                    layerIndex: 0,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: false
                )
            ],
            statusMessage: nil
        )
    }

    static var previewEmpty: SamoyedWidgetSnapshot {
        SamoyedWidgetSnapshot(
            date: LocalDay(year: 2026, month: 8, day: 12),
            minuteOfDay: 13 * 60 + 30,
            requiresTemplateSelection: false,
            currentBlockTitle: "Lunch",
            currentBlockTimeRangeText: "13:00 - 14:00",
            currentBlockNote: nil,
            blocks: [
                SamoyedWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Lunch",
                    layerIndex: 0,
                    timeRangeText: "13:00 - 14:00",
                    isBlank: false,
                    hasIncompleteTasks: false,
                    isCurrent: true
                )
            ],
            remainingTaskCount: 0,
            tasks: [],
            statusMessage: "No incomplete tasks in this chain."
        )
    }
}

#Preview("Small - Active", as: .systemSmall) {
    SamoyedNowWidget()
} timeline: {
    SamoyedNowWidgetEntry(date: .now, snapshot: .previewFocused)
}

#Preview("Medium - Active", as: .systemMedium) {
    SamoyedNowWidget()
} timeline: {
    SamoyedNowWidgetEntry(date: .now, snapshot: .previewFocused)
}

#Preview("Medium - Caught Up", as: .systemMedium) {
    SamoyedNowWidget()
} timeline: {
    SamoyedNowWidgetEntry(date: .now, snapshot: .previewEmpty)
}

#Preview("Accessory Inline", as: .accessoryInline) {
    SamoyedNowWidget()
} timeline: {
    SamoyedNowWidgetEntry(date: .now, snapshot: .previewFocused)
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    SamoyedNowWidget()
} timeline: {
    SamoyedNowWidgetEntry(date: .now, snapshot: .previewFocused)
}

#Preview("Accessory Circular", as: .accessoryCircular) {
    SamoyedNowWidget()
} timeline: {
    SamoyedNowWidgetEntry(date: .now, snapshot: .previewFocused)
}
