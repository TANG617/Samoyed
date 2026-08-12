import SwiftUI

struct TodayRootView: View {
    @Environment(ThingStructStore.self) private var store

    @State private var selection: TodaySelection?
    @State private var jumpToCurrentTrigger = 0
    @State private var scrollToBlockTrigger = 0
    @State private var scrollToBlockID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ScreenLoadingView(
                        title: "Loading Today",
                        systemImage: "calendar",
                        description: "Preparing your timeline and current context."
                    )
                } else if store.requiresTemplateSelection(for: store.selectedDate) {
                    RoutineSelectionRequiredView(
                        date: store.selectedDate,
                        title: "Choose a Routine",
                        message: "Pick one routine before Today can show the materialized timeline."
                    )
                } else {
                    RootScreenContainer(
                        isLoaded: true,
                        loadingTitle: "Loading Today",
                        loadingSystemImage: "calendar",
                        loadingDescription: "Preparing your timeline and current context.",
                        errorTitle: "Unable to Load Today",
                        retry: store.reload
                    ) {
                        try store.todayScreenModel(
                            currentDate: ThingStructSimulationClock.adjusted(.now)
                        )
                    } content: { model in
                        timelineContent(model: model)
                    }
                }
            }
            .navigationTitle(store.selectedDate.titleText)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: store.selectedDate) { _, _ in
            selection = store.selectedBlockID.map { .block(id: $0) }
        }
        .onChange(of: store.selectedBlockID) { _, newValue in
            guard let blockID = newValue else { return }
            selection = .block(id: blockID)
        }
        .onChange(of: store.selectedTab) { _, newValue in
            guard newValue != .today else { return }
            selection = nil
        }
        .onChange(of: selection) { _, newValue in
            if newValue == nil {
                store.selectBlock(nil)
            }
        }
    }

    private func timelineContent(model: TodayScreenModel) -> some View {
        let referenceDate = ThingStructSimulationClock.adjusted(.now)
        return TodayTimelineView(
            model: model,
            selectedBlockID: selection?.blockID,
            selectedOpenSlotID: selection?.openSlotID,
            currentMinute: store.currentMinuteOnSelectedDate(currentDate: referenceDate),
            jumpToCurrentTrigger: jumpToCurrentTrigger,
            scrollToBlockID: scrollToBlockID,
            scrollToBlockTrigger: scrollToBlockTrigger,
            timingResolver: { blockID in
                store.persistedBlock(on: store.selectedDate, blockID: blockID)?.timing
            },
            onSelectBlock: handleBlockSelection,
            onSelectOpenSlot: handleOpenSlotSelection,
            onClearSelection: clearSelection
        )
        .sheet(item: $selection) { presentedSelection in
            inspector(for: presentedSelection, model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.moveSelectedDate(by: -1)
                } label: {
                    Label("Previous Day", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Previous Day")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if store.selectedDate == .today() {
                    Button {
                        jumpToCurrent()
                    } label: {
                        Label("Jump to Now", systemImage: "location")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Jump to current time")
                } else {
                    Button("Today") {
                        store.selectDate(.today())
                    }
                    .accessibilityLabel("Go to Today")
                }

                Button {
                    store.moveSelectedDate(by: 1)
                } label: {
                    Label("Next Day", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Next Day")
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selection)
        .task(id: model.date) {
            syncSelectionForDisplayedDate(using: model)
        }
        .onChange(of: model.blocks.map(\.id)) { _, _ in
            validateSelection(using: model)
        }
        .onChange(of: model.openSlots.map(\.id)) { _, _ in
            validateSelection(using: model)
        }
    }

    @ViewBuilder
    private func inspector(for presentedSelection: TodaySelection, model: TodayScreenModel) -> some View {
        NavigationStack {
            inspectorContent(for: presentedSelection, model: model)
        }
    }

    @ViewBuilder
    private func inspectorContent(for presentedSelection: TodaySelection, model: TodayScreenModel) -> some View {
        switch presentedSelection {
        case let .block(id):
            if let detail = selectedBlockDetail(for: id) {
                TodayBlockInspectorView(
                    detail: detail,
                    onSelectParent: {
                        selectParentBlock(from: detail)
                    },
                    onToggleTask: { taskID in
                        store.toggleTask(on: model.date, blockID: detail.id, taskID: taskID)
                    }
                )
            } else if let block = model.blocks.first(where: { $0.id == id }) {
                TodayUnavailableInspectorView(
                    title: block.title,
                    startMinuteOfDay: block.startMinuteOfDay,
                    endMinuteOfDay: block.endMinuteOfDay
                )
            }

        case let .openSlot(id):
            if let slot = model.openSlots.first(where: { $0.id == id }) {
                TodayOpenSlotInspectorView(slot: slot)
            }
        }
    }

    private func syncSelectionForDisplayedDate(using model: TodayScreenModel) {
        guard model.date == store.selectedDate else { return }

        switch selection {
        case .none:
            if let blockID = store.selectedBlockID, model.blocks.contains(where: { $0.id == blockID }) {
                selection = .block(id: blockID)
            }

        case let .block(id) where model.blocks.contains(where: { $0.id == id }):
            store.selectBlock(id)

        case let .openSlot(id) where model.openSlots.contains(where: { $0.id == id }):
            store.selectBlock(nil)

        default:
            if let blockID = store.selectedBlockID, model.blocks.contains(where: { $0.id == blockID }) {
                selection = .block(id: blockID)
            } else {
                selection = nil
            }
        }
    }

    private func validateSelection(using model: TodayScreenModel) {
        switch selection {
        case .none:
            return

        case let .block(id):
            guard model.blocks.contains(where: { $0.id == id }) else {
                selection = nil
                store.selectBlock(nil)
                return
            }

        case let .openSlot(id):
            guard model.openSlots.contains(where: { $0.id == id }) else {
                selection = nil
                return
            }
        }
    }

    private func jumpToCurrent() {
        let blockID = store.currentActiveBlockID(
            currentDate: ThingStructSimulationClock.adjusted(.now)
        )
        store.selectBlock(blockID)
        selection = blockID.map { .block(id: $0) }
        jumpToCurrentTrigger += 1
    }

    private func handleBlockSelection(_ blockID: UUID) {
        store.selectBlock(blockID)
        selection = .block(id: blockID)
    }

    private func handleOpenSlotSelection(_ slotID: UUID) {
        store.selectBlock(nil)
        selection = .openSlot(id: slotID)
    }

    private func clearSelection() {
        selection = nil
        store.selectBlock(nil)
    }

    private func selectParentBlock(from detail: BlockDetailModel) {
        guard let parentID = detail.parentBlockID else { return }
        store.selectBlock(parentID)
        selection = .block(id: parentID)
        scrollToBlockID = parentID
        scrollToBlockTrigger += 1
    }

    private func selectedBlockDetail(for blockID: UUID) -> BlockDetailModel? {
        guard let detail = try? store.blockDetailModel(on: store.selectedDate, blockID: blockID) else {
            return nil
        }
        return detail
    }

}

private enum TodaySelection: Identifiable, Equatable {
    case block(id: UUID)
    case openSlot(id: UUID)

    var id: String {
        switch self {
        case let .block(id):
            return "block-\(id.uuidString)"
        case let .openSlot(id):
            return "open-slot-\(id.uuidString)"
        }
    }

    var blockID: UUID? {
        guard case let .block(id) = self else { return nil }
        return id
    }

    var openSlotID: UUID? {
        guard case let .openSlot(id) = self else { return nil }
        return id
    }
}

private struct TodayTimelineScale {
    let startHour: Int
    let endHour: Int
    let activeHours: Set<Int>

    private let denseHourHeight: CGFloat = 76
    private let quietHourHeight: CGFloat = 50
    let topInset: CGFloat = 14
    let bottomInset: CGFloat = 18

    init(model: TodayScreenModel, currentMinute: Int?) {
        let activeRanges = model.blocks.map { ($0.startMinuteOfDay, $0.endMinuteOfDay) }
        let ranges = activeRanges
            + model.openSlots.map { ($0.startMinuteOfDay, $0.endMinuteOfDay) }
        let rangeMinutes = ranges.flatMap { [$0.0, $0.1] } + [currentMinute].compactMap { $0 }
        let earliest = rangeMinutes.min() ?? 7 * 60
        let latest = rangeMinutes.max() ?? 18 * 60

        startHour = max(0, earliest / 60 - 1)
        endHour = min(24, Int(ceil(Double(latest) / 60.0)) + 1)

        var occupied = Set<Int>()
        for (start, end) in activeRanges {
            let firstHour = max(0, start / 60)
            let lastHour = min(23, max(firstHour, (max(start + 1, end) - 1) / 60))
            occupied.formUnion(firstHour ... lastHour)
        }
        if let currentMinute {
            occupied.insert(max(0, min(23, currentMinute / 60)))
        }
        activeHours = occupied
    }

    var hours: [Int] {
        Array(startHour ... endHour)
    }

    var canvasHeight: CGFloat {
        topInset
            + (startHour ..< endHour).reduce(CGFloat.zero) { $0 + hourHeight(for: $1) }
            + bottomInset
    }

    func yPosition(for minute: Int) -> CGFloat {
        let clamped = max(startHour * 60, min(endHour * 60, minute))
        let fullHour = min(endHour, clamped / 60)
        let completedHeight = (startHour ..< fullHour).reduce(CGFloat.zero) {
            $0 + hourHeight(for: $1)
        }
        guard fullHour < endHour else {
            return topInset + completedHeight
        }
        let fraction = CGFloat(clamped - fullHour * 60) / 60
        return topInset + completedHeight + hourHeight(for: fullHour) * fraction
    }

    func distance(from startMinute: Int, to endMinute: Int) -> CGFloat {
        max(0, yPosition(for: endMinute) - yPosition(for: startMinute))
    }

    func hourHeight(for hour: Int) -> CGFloat {
        activeHours.contains(hour) ? denseHourHeight : quietHourHeight
    }
}

private struct TodayTimelineView: View {
    let model: TodayScreenModel
    let selectedBlockID: UUID?
    let selectedOpenSlotID: UUID?
    let currentMinute: Int?
    let jumpToCurrentTrigger: Int
    let scrollToBlockID: UUID?
    let scrollToBlockTrigger: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let onSelectBlock: (UUID) -> Void
    let onSelectOpenSlot: (UUID) -> Void
    let onClearSelection: () -> Void

    @State private var lastInitialScrollDate: LocalDay?

    private let labelWidth: CGFloat = 52
    private let trackInset: CGFloat = 12

    private var scale: TodayTimelineScale {
        TodayTimelineScale(model: model, currentMinute: currentMinute)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onClearSelection)

                        hourGrid

                        ForEach(model.openSlots) { slot in
                            timelineOpenSlot(slot, canvasWidth: geometry.size.width)
                        }

                        ForEach(rootNodes) { node in
                            timelineBlock(node, canvasWidth: geometry.size.width)
                        }

                        if let currentMinute {
                            currentTimeLine(minute: currentMinute, canvasWidth: geometry.size.width)
                                .zIndex(100)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geometry.size.width, height: canvasHeight, alignment: .topLeading)
                }
                .frame(height: canvasHeight)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: model.date) {
                guard lastInitialScrollDate != model.date else { return }
                lastInitialScrollDate = model.date

                if let focusBlockID = model.initialFocusBlockID,
                   let fallbackMinute = currentMinute ?? model.blocks.first(where: { $0.id == focusBlockID })?.startMinuteOfDay {
                    scroll(
                        toBlock: focusBlockID,
                        fallbackMinute: fallbackMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: false
                    )
                } else if let currentMinute {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: false)
                } else {
                    scroll(to: model.initialScrollMinute, anchor: .top, proxy: proxy, animated: false)
                }
            }
            .onChange(of: jumpToCurrentTrigger) { _, _ in
                if let selectedBlockID {
                    scroll(
                        toBlock: selectedBlockID,
                        fallbackMinute: currentMinute ?? model.initialScrollMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: true
                    )
                } else if let currentMinute {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: true)
                }
            }
            .onChange(of: scrollToBlockTrigger) { _, _ in
                guard let scrollToBlockID else { return }
                scroll(
                    toBlock: scrollToBlockID,
                    fallbackMinute: currentMinute ?? model.initialScrollMinute,
                    anchor: .center,
                    proxy: proxy,
                    animated: true
                )
            }
        }
    }

    private var hourGrid: some View {
        ForEach(scale.hours, id: \.self) { hour in
            let y = scale.yPosition(for: hour * 60)
            HStack(spacing: 0) {
                Text(hourLabel(for: hour))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .offset(y: -8)

                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 1)
            }
            .frame(height: 1)
            .offset(y: y)
            .id(hour)
        }
    }

    private func currentTimeLine(minute: Int, canvasWidth: CGFloat) -> some View {
        let y = scale.yPosition(for: minute)
        return HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .offset(x: labelWidth - 4)

            Rectangle()
                .fill(.red)
                .frame(height: 2)
        }
        .frame(width: canvasWidth, alignment: .leading)
        .offset(y: y)
    }

    private func timelineBlock(_ node: TodayTimelineNode, canvasWidth: CGFloat) -> some View {
        let startDelta = propagatedStartDelta(
            for: node.block.id,
            timing: timingResolver(node.block.id),
            inheritedStartDelta: 0
        )
        let displayedStartMinuteOfDay = displayedStartMinute(
            for: node.block.id,
            originalStartMinuteOfDay: node.block.startMinuteOfDay,
            startDelta: startDelta
        )
        let displayedEndMinuteOfDay = displayedEndMinute(
            for: node.block.id,
            originalEndMinuteOfDay: node.block.endMinuteOfDay,
            startDelta: startDelta
        )
        let y = scale.yPosition(for: displayedStartMinuteOfDay)
        let blockWidth = max(0, canvasWidth - labelWidth - trackInset * 2)

        return TimelineBlockCard(
            node: node,
            scale: scale,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedStartMinuteOfDay: displayedStartMinuteOfDay,
            displayedEndMinuteOfDay: displayedEndMinuteOfDay,
            inheritedStartDelta: startDelta,
            timingResolver: timingResolver,
            onSelect: onSelectBlock
        )
        .frame(width: blockWidth, alignment: .leading)
        .offset(x: labelWidth + trackInset, y: y)
    }

    private func timelineOpenSlot(_ slot: TodayOpenSlotItem, canvasWidth: CGFloat) -> some View {
        let y = scale.yPosition(for: slot.startMinuteOfDay)
        let trackWidth = max(0, canvasWidth - labelWidth - trackInset * 2)

        return TimelineOpenSlotEntry(
            slot: slot,
            scale: scale,
            isSelected: selectedOpenSlotID == slot.id,
            onSelect: { onSelectOpenSlot(slot.id) }
        )
        .frame(width: trackWidth, alignment: .leading)
        .offset(x: labelWidth + trackInset, y: y)
    }

    private var canvasHeight: CGFloat {
        scale.canvasHeight
    }

    private var blocksByID: [UUID: TimelineBlockItem] {
        Dictionary(uniqueKeysWithValues: model.blocks.map { ($0.id, $0) })
    }

    private var rootNodes: [TodayTimelineNode] {
        let childrenByParent = Dictionary(grouping: model.blocks.filter { $0.parentBlockID != nil }) { $0.parentBlockID! }
            .mapValues { $0.sorted(by: timelineNodeSort) }

        func buildNode(for block: TimelineBlockItem) -> TodayTimelineNode {
            TodayTimelineNode(
                block: block,
                children: (childrenByParent[block.id] ?? []).map(buildNode)
            )
        }

        return model.blocks
            .filter { $0.parentBlockID == nil }
            .sorted(by: timelineNodeSort)
            .map(buildNode)
    }

    private var selectedPathIDs: Set<UUID> {
        guard let selectedBlockID else { return [] }

        var path = Set([selectedBlockID])
        var cursor = blocksByID[selectedBlockID]?.parentBlockID

        while let parentID = cursor {
            path.insert(parentID)
            cursor = blocksByID[parentID]?.parentBlockID
        }

        return path
    }

    private func anchorHour(for minute: Int) -> Int {
        max(scale.startHour, min(scale.endHour, minute / 60))
    }

    private func hourLabel(for hour: Int) -> String {
        if hour == 24 {
            return "24:00"
        }

        return String(format: "%02d:00", hour)
    }

    private func scroll(to minute: Int, anchor: UnitPoint, proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(anchorHour(for: minute), anchor: anchor)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                action()
            }
        } else {
            action()
        }
    }

    private func scroll(
        toBlock blockID: UUID,
        fallbackMinute: Int,
        anchor: UnitPoint,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            if blocksByID[blockID] != nil {
                proxy.scrollTo(blockID, anchor: anchor)
            } else {
                proxy.scrollTo(anchorHour(for: fallbackMinute), anchor: anchor)
            }
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                action()
            }
        } else {
            action()
        }
    }

    private func timelineNodeSort(_ lhs: TimelineBlockItem, _ rhs: TimelineBlockItem) -> Bool {
        if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
            return lhs.startMinuteOfDay < rhs.startMinuteOfDay
        }
        if lhs.layerIndex != rhs.layerIndex {
            return lhs.layerIndex < rhs.layerIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct TodayTimelineNode: Identifiable {
    let block: TimelineBlockItem
    let children: [TodayTimelineNode]

    var id: UUID { block.id }
}

private func propagatedStartDelta(
    for blockID: UUID,
    timing: TimeBlockTiming?,
    inheritedStartDelta: Int
) -> Int {
    guard inheritedStartDelta != 0 else {
        return 0
    }

    guard case .relative? = timing else {
        return 0
    }

    return inheritedStartDelta
}

private func displayedStartMinute(
    for blockID: UUID,
    originalStartMinuteOfDay: Int,
    startDelta: Int
) -> Int {
    return originalStartMinuteOfDay + startDelta
}

private func displayedEndMinute(
    for blockID: UUID,
    originalEndMinuteOfDay: Int,
    startDelta: Int
) -> Int {
    return originalEndMinuteOfDay + startDelta
}

private struct TimelineBlockCard: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let node: TodayTimelineNode
    let scale: TodayTimelineScale
    let selectedBlockID: UUID?
    let selectedPathIDs: Set<UUID>
    let displayedStartMinuteOfDay: Int
    let displayedEndMinuteOfDay: Int
    let inheritedStartDelta: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let onSelect: (UUID) -> Void

    private let minimumHeight: CGFloat = 52
    private let childInset: CGFloat = 16
    private let childGap: CGFloat = 8
    private let maximumVerticalGap: CGFloat = 3

    private var block: TimelineBlockItem { node.block }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: block.layerIndex,
            isBlank: false,
            preset: tintPreset
        )
    }

    private var isSelected: Bool {
        selectedBlockID == block.id
    }

    private var isSelectedAncestor: Bool {
        selectedPathIDs.contains(block.id) && !isSelected
    }

    private var nodeStartDelta: Int {
        propagatedStartDelta(
            for: block.id,
            timing: timingResolver(block.id),
            inheritedStartDelta: inheritedStartDelta
        )
    }

    private var durationHeight: CGFloat {
        scale.distance(from: displayedStartMinuteOfDay, to: displayedEndMinuteOfDay)
    }

    private var outerFrameHeight: CGFloat {
        max(durationHeight, minimumHeight)
    }

    private var visualVerticalInset: CGFloat {
        let availableGap = max(0, durationHeight - minimumHeight)
        return min(maximumVerticalGap / 2, availableGap / 2)
    }

    private var cardHeight: CGFloat {
        outerFrameHeight - visualVerticalInset * 2
    }

    private var headerReservedHeight: CGFloat {
        54
    }

    private var headerBackdropHeight: CGFloat {
        min(cardHeight, headerReservedHeight + 22)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: max(18, 22 - CGFloat(min(2, block.layerIndex)) * 2),
            style: .continuous
        )
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(block.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }

            Text("\(displayedStartMinuteOfDay.formattedTime) - \(displayedEndMinuteOfDay.formattedTime)")
                .font(.caption)
                .foregroundStyle(.secondary)

        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    backgroundColor,
                    backgroundColor,
                    backgroundColor.opacity(0.96),
                    backgroundColor.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerBackdropHeight)
            .clipShape(cardShape)
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        GeometryReader { geometry in
            let childHorizontalInset = min(childInset, max(8, geometry.size.width * 0.12))
            let childWidth = max(geometry.size.width - childHorizontalInset * 2, 1)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    cardShape
                        .fill(backgroundColor)

                    selectionSurface

                    ForEach(Array(node.children), id: \.id) { child in
                        childCard(
                            for: child,
                            width: childWidth,
                            horizontalInset: childHorizontalInset
                        )
                    }

                    headerContent
                        .zIndex(1)

                }
                .clipShape(cardShape)
                .frame(width: geometry.size.width, height: cardHeight, alignment: .topLeading)
                .offset(y: visualVerticalInset)
                .overlay(
                    cardShape
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .shadow(
                    color: isSelected ? style.accent.opacity(0.16) : .clear,
                    radius: 10,
                    y: 4
                )
            }
        }
        .frame(height: outerFrameHeight)
        .id(block.id)
        .onTapGesture {
            onSelect(block.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows block details")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect(block.id)
        }
    }

    private var accessibilityLabel: String {
        [
            block.title,
            "\(displayedStartMinuteOfDay.formattedTime) to \(displayedEndMinuteOfDay.formattedTime)"
        ]
        .joined(separator: ", ")
    }

    private var backgroundColor: Color {
        if isSelected {
            return style.strongSurface
        }

        if isSelectedAncestor {
            return style.surface.opacity(0.94)
        }

        return node.children.isEmpty ? style.surface : style.surface.opacity(0.9)
    }

    private var borderColor: Color {
        if isSelected {
            return style.accent
        }

        if isSelectedAncestor {
            return style.accent.opacity(0.42)
        }

        return style.border
    }

    private var borderWidth: CGFloat {
        if isSelected {
            return 2.2
        }

        if isSelectedAncestor {
            return 1.5
        }

        return 1
    }

    private func childYOffset(for child: TodayTimelineNode, childHeight: CGFloat) -> CGFloat {
        let childRange = childDisplayedRange(of: child)
        let relative = scale.distance(
            from: displayedStartMinuteOfDay,
            to: childRange.startMinuteOfDay
        )
        let desiredTop = headerReservedHeight + childGap
        let availableShift = max(0, cardHeight - childHeight - childGap - relative)
        let shift = min(max(0, desiredTop - relative), availableShift)
        return relative + shift
    }

    private func childCard(
        for child: TodayTimelineNode,
        width: CGFloat,
        horizontalInset: CGFloat
    ) -> some View {
        let childRange = childDisplayedRange(of: child)
        let childHeight = max(
            scale.distance(
                from: childRange.startMinuteOfDay,
                to: childRange.endMinuteOfDay
            ),
            minimumHeight
        )

        return TimelineBlockCard(
            node: child,
            scale: scale,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedStartMinuteOfDay: childRange.startMinuteOfDay,
            displayedEndMinuteOfDay: childRange.endMinuteOfDay,
            inheritedStartDelta: nodeStartDelta,
            timingResolver: timingResolver,
            onSelect: onSelect
        )
        .frame(width: width)
        .offset(
            x: horizontalInset,
            y: childYOffset(for: child, childHeight: childHeight)
        )
    }

    private func childDisplayedRange(of child: TodayTimelineNode) -> (startMinuteOfDay: Int, endMinuteOfDay: Int) {
        let startDelta = propagatedStartDelta(
            for: child.block.id,
            timing: timingResolver(child.block.id),
            inheritedStartDelta: nodeStartDelta
        )

        return (
            startMinuteOfDay: displayedStartMinute(
                for: child.block.id,
                originalStartMinuteOfDay: child.block.startMinuteOfDay,
                startDelta: startDelta
            ),
            endMinuteOfDay: displayedEndMinute(
                for: child.block.id,
                originalEndMinuteOfDay: child.block.endMinuteOfDay,
                startDelta: startDelta
            )
        )
    }

    private var selectionSurface: some View {
        Color.clear
            .contentShape(cardShape)
            .onTapGesture {
                onSelect(block.id)
            }
    }

}

private struct TimelineOpenSlotEntry: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let slot: TodayOpenSlotItem
    let scale: TodayTimelineScale
    let isSelected: Bool
    let onSelect: () -> Void

    private var slotHeight: CGFloat {
        scale.distance(from: slot.startMinuteOfDay, to: slot.endMinuteOfDay)
    }

    private var showsTimeRange: Bool {
        slotHeight >= 54
    }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: 0,
            isBlank: true,
            preset: tintPreset
        )
    }

    private var timeRangeText: String {
        "\(slot.startMinuteOfDay.formattedTime) - \(slot.endMinuteOfDay.formattedTime)"
    }

    private var accessibilityText: String {
        "Open Time, \(slot.startMinuteOfDay.formattedTime) to \(slot.endMinuteOfDay.formattedTime)"
    }

    private var overlayAlignment: Alignment {
        showsTimeRange ? .leading : .center
    }

    var body: some View {
        slotShape
            .fill(isSelected ? style.surface.opacity(0.55) : style.surface.opacity(0.18))
            .overlay(slotBorder)
            .frame(height: max(slotHeight, 10))
            .overlay(alignment: overlayAlignment) { slotLabel }
            .contentShape(slotShape)
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Shows open time details")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onSelect()
            }
    }

    private var slotShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var slotBorder: some View {
        slotShape.strokeBorder(
            isSelected ? style.accent.opacity(0.88) : style.border.opacity(0.55),
            style: StrokeStyle(lineWidth: isSelected ? 1.6 : 1, dash: [6, 6])
        )
    }

    private var slotLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(isSelected ? style.accent : .secondary)

            if showsTimeRange {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Time")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(timeRangeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

private struct TodayBlockInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let detail: BlockDetailModel
    let onSelectParent: () -> Void
    let onToggleTask: (UUID) -> Void

    var body: some View {
        Form {
            Section {
                header
            }

            if detail.parentBlockTitle != nil {
                Section {
                    parentButton
                }
            }

            Section("Note") {
                if let note = detail.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No note")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Checklist") {
                if detail.tasks.isEmpty {
                    Text("No checklist items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.tasks) { task in
                        Button {
                            onToggleTask(task.id)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.accentColor)
                                    .font(.title3)

                                Text(task.title)
                                    .strikethrough(task.isCompleted, color: .secondary)
                                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task.title)
                        .accessibilityValue(task.isCompleted ? "Completed" : "Not completed")
                        .accessibilityHint("Toggles this checklist item")
                    }
                }
            }

            Section("Reminders") {
                if detail.reminders.isEmpty {
                    Text("No reminders")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(detail.reminders) { reminder in
                            Label(reminderSummary(reminder), systemImage: "bell.badge")
                                .font(.body)
                        }
                    }
                }
            }
        }
        .navigationTitle("Block Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(detail.startMinuteOfDay.formattedTime) - \(detail.endMinuteOfDay.formattedTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var parentButton: some View {
        Button(action: onSelectParent) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Parent Block")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(detail.parentBlockTitle ?? "")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parent block, \(detail.parentBlockTitle ?? "")")
    }

    private func reminderSummary(_ reminder: ReminderRule) -> String {
        if let preset = ReminderPreset(rule: reminder) {
            return preset.title
        }

        switch reminder.triggerMode {
        case .atStart:
            return "At start"
        case .beforeStart:
            return "\(reminder.offsetMinutes) min before"
        }
    }
}

private struct TodayOpenSlotInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let slot: TodayOpenSlotItem

    var body: some View {
        Form {
            Section {
                LabeledContent("Time", value: "\(slot.startMinuteOfDay.formattedTime) - \(slot.endMinuteOfDay.formattedTime)")
                LabeledContent("Duration", value: durationText)
            }

            Section {
                Text("This gap is free in the selected routine projection.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Open Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var durationText: String {
        let hours = slot.durationMinutes / 60
        let minutes = slot.durationMinutes % 60

        switch (hours, minutes) {
        case (0, let minutes):
            return "\(minutes) min available"
        case (let hours, 0):
            return hours == 1 ? "1 hour available" : "\(hours) hours available"
        default:
            return "\(hours)h \(minutes)m available"
        }
    }
}

private struct TodayUnavailableInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int

    var body: some View {
        Form {
            Section {
                Text(title)
                    .font(.headline)

                Text("\(startMinuteOfDay.formattedTime) - \(endMinuteOfDay.formattedTime)")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("This block is no longer available in the current day plan.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Unavailable Block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview("Today Root") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today))
}

#Preview("Today Root - Empty Day") {
    TodayRootView()
        .environment(
            PreviewSupport.store(
                tab: .today,
                document: ThingStructDocument()
            )
        )
}

#Preview("Today Root - Loading") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today, loaded: false))
}

#Preview("Today Timeline") {
    let model = PreviewSupport.todayModel()
    TodayTimelineView(
        model: model,
        selectedBlockID: model.selectedBlock?.id,
        selectedOpenSlotID: nil,
        currentMinute: 9 * 60 + 30,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}

#Preview("Today Timeline - Blank") {
    let model = PreviewSupport.todayModel(document: ThingStructDocument(), currentMinute: nil)
    TodayTimelineView(
        model: model,
        selectedBlockID: nil,
        selectedOpenSlotID: nil,
        currentMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}

#Preview("Today Timeline - Historical Day") {
    let day = PreviewSupport.referenceDay.adding(days: -1)
    let document = PreviewSupport.seededDocument(on: day)
    let model = try! ThingStructPresentation.todayScreenModel(
        document: document,
        date: day,
        selectedBlockID: nil,
        currentMinute: nil
    )
    TodayTimelineView(
        model: model,
        selectedBlockID: model.selectedBlock?.id,
        selectedOpenSlotID: nil,
        currentMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}
