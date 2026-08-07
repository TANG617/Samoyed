import SwiftUI

private enum TodaySheetDestination: Identifiable {
    case block(UUID)
    case todayDifferent

    var id: String {
        switch self {
        case let .block(id): "block-\(id.uuidString)"
        case .todayDifferent: "today-different"
        }
    }
}

struct TodayRootView: View {
    @Environment(ThingStructStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: TodaySheetDestination?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                RootScreenContainer(
                    isLoaded: store.isReady,
                    loadingTitle: "Loading Today",
                    loadingSystemImage: "calendar",
                    loadingDescription: "Preparing the whole-day view.",
                    errorTitle: "Unable to Build Today",
                    retry: store.reload
                ) {
                    try store.todayScreenModel(currentDate: context.date)
                } content: { model in
                    if dynamicTypeSize.isAccessibilitySize {
                        TodayAgendaView(model: model, select: select)
                    } else {
                        TodayTimelineView(
                            model: model,
                            currentMinute: store.currentMinuteOnSelectedDate(currentDate: context.date),
                            select: select
                        )
                    }
                }
            }
            .navigationTitle(store.selectedDate.nowNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.selectedDate == .today() {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            sheet = .todayDifferent
                        } label: {
                            Label("Today is different", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                    }
                }
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case let .block(blockID):
                TodayBlockDetailSheet(date: store.selectedDate, blockID: blockID)
                    .environment(store)
            case .todayDifferent:
                TodayDifferentSheet(date: .today())
                    .environment(store)
            }
        }
    }

    private func select(_ blockID: UUID) {
        sheet = .block(blockID)
    }
}

private struct TodayTimelineView: View {
    let model: TodayScreenModel
    let currentMinute: Int?
    let select: (UUID) -> Void

    private let hourHeight: CGFloat = 64
    private let rulerWidth: CGFloat = 58

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        ForEach(model.blocks) { block in
                            timelineBlock(block, availableWidth: geometry.size.width)
                        }
                        if let currentMinute {
                            currentTimeLine(minute: currentMinute, width: geometry.size.width)
                        }
                    }
                    .frame(height: 24 * hourHeight)
                }
                .frame(height: 24 * hourHeight)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                let hour = min(max((model.initialScrollMinute - 60) / 60, 0), 23)
                DispatchQueue.main.async {
                    proxy.scrollTo("hour-\(hour)", anchor: .top)
                }
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text((hour * 60).formattedTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: rulerWidth - 10, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle()
                        .fill(Color.secondary.opacity(hour.isMultiple(of: 2) ? 0.16 : 0.08))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour-\(hour)")
            }
        }
    }

    private func timelineBlock(_ block: TimelineBlockItem, availableWidth: CGFloat) -> some View {
        let start = CGFloat(block.startMinuteOfDay) / 60 * hourHeight
        let duration = CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / 60 * hourHeight
        let layerOffset = CGFloat(min(block.layerIndex, 3)) * 12
        let width = max(availableWidth - rulerWidth - layerOffset - 16, 120)
        let style = LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: false)

        return Button {
            select(block.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(block.startMinuteOfDay.formattedTime)–\(block.endMinuteOfDay.formattedTime)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(style.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: max(duration - 4, 44), alignment: .topLeading)
        .offset(x: rulerWidth + layerOffset, y: start + 2)
        .accessibilityLabel("\(block.title), \(block.startMinuteOfDay.formattedTime) to \(block.endMinuteOfDay.formattedTime)")
        .accessibilityHint("Opens today-only details")
    }

    private func currentTimeLine(minute: Int, width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
        .frame(width: max(width - rulerWidth + 4, 0), alignment: .leading)
        .offset(x: rulerWidth - 4, y: CGFloat(minute) / 60 * hourHeight)
        .accessibilityHidden(true)
    }
}

private struct TodayAgendaView: View {
    let model: TodayScreenModel
    let select: (UUID) -> Void

    private var entries: [AgendaEntry] {
        let blocks = model.blocks.map(AgendaEntry.block)
        let open = model.openSlots
            .filter { $0.durationMinutes >= 15 }
            .map(AgendaEntry.open)
        return (blocks + open).sorted { $0.startMinute < $1.startMinute }
    }

    var body: some View {
        List(entries) { entry in
            switch entry {
            case let .block(block):
                Button {
                    select(block.id)
                } label: {
                    AgendaBlockRow(block: block)
                }
                .buttonStyle(.plain)
            case let .open(slot):
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(slot.startMinuteOfDay.formattedTime)–\(slot.endMinuteOfDay.formattedTime)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Open time")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.plain)
    }
}

private enum AgendaEntry: Identifiable {
    case block(TimelineBlockItem)
    case open(TodayOpenSlotItem)

    var id: String {
        switch self {
        case let .block(block): "block-\(block.id.uuidString)"
        case let .open(slot): "open-\(slot.id.uuidString)"
        }
    }

    var startMinute: Int {
        switch self {
        case let .block(block): block.startMinuteOfDay
        case let .open(slot): slot.startMinuteOfDay
        }
    }
}

private struct AgendaBlockRow: View {
    let block: TimelineBlockItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(block.startMinuteOfDay.formattedTime)–\(block.endMinuteOfDay.formattedTime)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(block.title)
                .font(.headline)
            if block.incompleteTaskCount > 0 {
                Text("\(block.incompleteTaskCount) checklist items")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint("Opens today-only details")
    }
}

private struct TodayCorrectionTarget: Identifiable {
    let id: UUID
}

private struct TodayBlockDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThingStructStore.self) private var store
    let date: LocalDay
    let blockID: UUID
    @State private var correction: TodayCorrectionTarget?

    var body: some View {
        NavigationStack {
            Group {
                if let detail = try? store.blockDetailModel(on: date, blockID: blockID) {
                    List {
                        Section("Time") {
                            LabeledContent("Starts", value: detail.startMinuteOfDay.formattedTime)
                            LabeledContent("Ends", value: detail.endMinuteOfDay.formattedTime)
                            if let parent = detail.parentBlockTitle {
                                LabeledContent("Part of", value: parent)
                            }
                        }
                        if let note = detail.note, !note.isEmpty {
                            Section("Note") {
                                Text(note)
                            }
                        }
                        Section("Checklist") {
                            if detail.tasks.isEmpty {
                                Text("No checklist items")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(detail.tasks) { task in
                                    Label(
                                        task.title,
                                        systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle"
                                    )
                                }
                            }
                        }
                    }
                } else {
                    RecoverableErrorView(
                        title: "Block Unavailable",
                        message: "This block could not be loaded.",
                        retry: dismiss.callAsFunction
                    )
                }
            }
            .navigationTitle((try? store.blockDetailModel(on: date, blockID: blockID))?.title ?? "Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if date == .today() {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Edit Today") {
                            correction = TodayCorrectionTarget(id: blockID)
                        }
                        .accessibilityIdentifier("today-edit")
                    }
                }
            }
        }
        .sheet(item: $correction) { target in
            TodayCorrectionSheet(date: date, blockID: target.id)
                .environment(store)
        }
    }
}

private struct TodayCorrectionForm: Equatable {
    var title: String
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var note: String
    var tasks: [TaskItem]
}

private struct TodayCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThingStructStore.self) private var store
    let date: LocalDay
    let blockID: UUID

    @State private var form: TodayCorrectionForm?
    @State private var errorMessage: String?
    @State private var startedAt = Date.now
    @State private var didFinish = false

    var body: some View {
        NavigationStack {
            Group {
                if let formBinding = Binding($form) {
                    Form {
                        Section {
                            Text("Changes here apply only to today. Your saved day type stays unchanged.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Section("Block") {
                            TextField("Title", text: formBinding.title)
                                .accessibilityIdentifier("today-correction-title")
                            LabeledContent("Starts") {
                                MinuteTimePicker(minuteOfDay: formBinding.startMinuteOfDay)
                            }
                            LabeledContent("Ends") {
                                MinuteTimePicker(minuteOfDay: formBinding.endMinuteOfDay)
                            }
                            TextField("Note", text: formBinding.note, axis: .vertical)
                                .lineLimit(2 ... 5)
                        }
                        Section("Checklist") {
                            ForEach(formBinding.tasks) { $task in
                                TextField("Checklist item", text: $task.title)
                            }
                            .onDelete { formBinding.wrappedValue.tasks.remove(atOffsets: $0) }
                            Button {
                                formBinding.wrappedValue.tasks.append(TaskItem(title: ""))
                            } label: {
                                Label("Add Checklist Item", systemImage: "plus")
                            }
                        }
                        if let errorMessage {
                            Section {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } else {
                    ProgressView("Loading Block")
                }
            }
            .navigationTitle("Edit Today Only")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        finish(outcome: "cancelled")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(form == nil)
                        .accessibilityIdentifier("today-correction-save")
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear {
            if !didFinish { finish(outcome: "dismissed") }
        }
    }

    private func load() {
        guard form == nil else { return }
        startedAt = .now
        store.recordValidationEvent(.todayCorrectionOpened, outcome: "opened", at: startedAt)
        do {
            guard let detail = try store.blockDetailModel(on: date, blockID: blockID) else {
                throw ThingStructCoreError.missingBlock(blockID)
            }
            form = TodayCorrectionForm(
                title: detail.title,
                startMinuteOfDay: detail.startMinuteOfDay,
                endMinuteOfDay: detail.endMinuteOfDay,
                note: detail.note ?? "",
                tasks: detail.tasks
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let form else { return }
        do {
            try store.applyTodayCorrection(
                TodayBlockCorrection(
                    blockID: blockID,
                    title: form.title,
                    startMinuteOfDay: form.startMinuteOfDay,
                    endMinuteOfDay: form.endMinuteOfDay,
                    note: form.note,
                    tasks: form.tasks
                ),
                on: date
            )
            finish(outcome: "saved")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish(outcome: String) {
        guard !didFinish else { return }
        didFinish = true
        store.recordValidationEvent(
            .todayCorrectionCompleted,
            outcome: outcome,
            variant: "today-only",
            durationMilliseconds: Int(Date.now.timeIntervalSince(startedAt) * 1_000)
        )
    }
}

#Preview("Today") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today))
}
