import SwiftUI

struct RoutinesRootView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var pendingTodayChoice: PendingTodayChoice?

    var body: some View {
        RootScreenContainer(
            isLoaded: store.isLoaded,
            loadingTitle: "Loading Routines",
            loadingSystemImage: "square.stack.3d.up",
            loadingDescription: "Preparing today’s routine choice and your local routine library.",
            errorTitle: "Unable to Load Routines",
            retry: store.reload,
            load: { try store.templatesScreenModel() }
        ) { model in
            List {
                todaySection(model: model)
                availableSection(model: model)
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RoutineEditorView(mode: .create)
                } label: {
                    Label("New Routine", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            "Switch today’s routine?",
            isPresented: Binding(
                get: { pendingTodayChoice != nil },
                set: { if !$0 { pendingTodayChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Switch Routine", role: .destructive) {
                guard let pendingTodayChoice else { return }
                chooseForToday(
                    templateID: pendingTodayChoice.templateID,
                    forceReplace: true
                )
            }
            Button("Keep Current Routine", role: .cancel) {
                pendingTodayChoice = nil
            }
        } message: {
            Text("Today already has execution state. Switching routines may reset checklist completion.")
        }
    }

    @ViewBuilder
    private func todaySection(model: TemplatesScreenModel) -> some View {
        Section {
            if let current = model.todayChooser.currentSelection {
                NavigationLink {
                    RoutineDetailView(routineID: current.id)
                } label: {
                    RoutineListRow(
                        routine: current,
                        subtitle: "Selected for today",
                        isSelected: true
                    )
                }
            } else {
                ContentUnavailableView(
                    "Choose Today’s Routine",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Select one routine before Now and Today enter running mode.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } header: {
            Text("Today")
        }
    }

    @ViewBuilder
    private func availableSection(model: TemplatesScreenModel) -> some View {
        Section {
            if model.savedTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No Routines", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Create a reusable routine or import a Routine Config File.")
                } actions: {
                    Button {
                        store.openLibrary(destination: .routineFiles)
                    } label: {
                        Label("Import Routine Config File", systemImage: "square.and.arrow.down")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(model.savedTemplates) { routine in
                    NavigationLink {
                        RoutineDetailView(routineID: routine.id)
                    } label: {
                        RoutineListRow(
                            routine: routine,
                            subtitle: routine.timeRangeText ?? "Reusable routine",
                            isSelected: routine.isCurrentForToday
                        )
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            chooseForToday(templateID: routine.id, forceReplace: false)
                        } label: {
                            Label("Today", systemImage: "calendar.badge.checkmark")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        } header: {
            Text("Available")
        } footer: {
            Text("Open a routine to review its block structure, notes, tasks, and schedule.")
        }
    }

    private func chooseForToday(templateID: UUID, forceReplace: Bool) {
        do {
            let result = try store.chooseTemplate(
                for: .today(),
                templateID: templateID,
                source: .pickedTemplate,
                forceReplace: forceReplace
            )
            switch result {
            case .applied:
                pendingTodayChoice = nil
            case .requiresConfirmation:
                pendingTodayChoice = PendingTodayChoice(templateID: templateID)
            }
        } catch {
            store.presentError(error)
        }
    }
}

private struct PendingTodayChoice: Equatable {
    let templateID: UUID
}

private struct RoutineListRow: View {
    let routine: TemplateCandidateSummary
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.body)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected for today")
            }
        }
    }
}

struct RoutineDetailView: View {
    @Environment(SamoyedStore.self) private var store
    @State private var isConfirmingReplacement = false
    @State private var isEditing = false
    @State private var renderedBlocks: [TimeBlock] = []

    let routineID: UUID

    private var routine: SavedDayTemplate? {
        store.savedTemplate(id: routineID)
    }

    private var isCurrentForToday: Bool {
        store.document.daySelection(for: .today())?.selectedTemplateID == routineID
            || store.document.dayPlan(for: .today())?.sourceSavedTemplateID == routineID
    }

    private var previewBlocks: [TimeBlock] {
        renderedBlocks
    }

    private var timeRangeText: String {
        guard
            let start = previewBlocks.compactMap(\.resolvedStartMinuteOfDay).min(),
            let end = previewBlocks.compactMap(\.resolvedEndMinuteOfDay).max()
        else {
            return "No schedule"
        }
        return "\(start.formattedTime) - \(end.formattedTime)"
    }

    var body: some View {
        Group {
            if let routine {
                List {
                    Section("Schedule") {
                        LabeledContent("Time", value: timeRangeText)
                        LabeledContent("Blocks", value: "\(routine.blocks.count)")
                        LabeledContent(
                            "Reminders",
                            value: "\(routine.blocks.reduce(0) { $0 + $1.reminders.count })"
                        )
                    }

                    Section("Template") {
                        ForEach(previewBlocks) { block in
                            RoutineTemplateBlockRow(
                                block: block,
                                childTitles: previewBlocks
                                    .filter { $0.parentBlockID == block.id }
                                    .map(\.title)
                            )
                        }
                    }

                    Section {
                        Button {
                            selectForToday(forceReplace: false)
                        } label: {
                            Label(
                                isCurrentForToday ? "Selected for Today" : "Select for Today",
                                systemImage: isCurrentForToday
                                    ? "checkmark.circle.fill"
                                    : "calendar.badge.checkmark"
                            )
                        }
                        .disabled(isCurrentForToday)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(routine.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
                .navigationDestination(isPresented: $isEditing) {
                    RoutineEditorView(mode: .edit(routine.id))
                }
            } else {
                ContentUnavailableView(
                    "Routine Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This routine may have been deleted or replaced.")
                )
            }
        }
        .confirmationDialog(
            "Replace today’s routine?",
            isPresented: $isConfirmingReplacement,
            titleVisibility: .visible
        ) {
            Button("Replace Routine", role: .destructive) {
                selectForToday(forceReplace: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today already has execution state. Replacing it may reset checklist completion.")
        }
        .task(id: routine?.updatedAt) {
            refreshPreview()
        }
    }

    private func selectForToday(forceReplace: Bool) {
        do {
            switch try store.chooseTemplate(
                for: .today(),
                templateID: routineID,
                source: .pickedTemplate,
                forceReplace: forceReplace
            ) {
            case .applied:
                isConfirmingReplacement = false
            case .requiresConfirmation:
                isConfirmingReplacement = true
            }
        } catch {
            store.presentError(error)
        }
    }

    private func routineBlockSort(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Bool {
        if lhs.layerIndex != rhs.layerIndex { return lhs.layerIndex < rhs.layerIndex }
        if lhs.resolvedStartMinuteOfDay != rhs.resolvedStartMinuteOfDay {
            return (lhs.resolvedStartMinuteOfDay ?? 0) < (rhs.resolvedStartMinuteOfDay ?? 0)
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func refreshPreview() {
        guard let routine, let preview = try? TemplateEngine.previewDayPlan(from: routine) else {
            renderedBlocks = []
            return
        }
        renderedBlocks = preview.blocks
            .filter { !$0.isCancelled && !$0.isBlankBaseBlock }
            .sorted(by: routineBlockSort)
    }
}

private struct RoutineTemplateBlockRow: View {
    @Environment(\.samoyedTintPreset) private var tintPreset
    @State private var isExpanded = true

    let block: TimeBlock
    let childTitles: [String]

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: block.layerIndex,
            isBlank: false,
            preset: tintPreset
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                if let note = block.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    detailGroup(title: "Note") {
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !block.tasks.isEmpty {
                    detailGroup(title: "Tasks") {
                        ForEach(block.tasks.sorted(by: taskOrder)) { task in
                            Label(task.title, systemImage: "circle")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                if !childTitles.isEmpty {
                    detailGroup(title: "Child Blocks") {
                        ForEach(childTitles, id: \.self) { title in
                            Label(title, systemImage: "square.stack.3d.up")
                        }
                    }
                }

                if block.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                   block.tasks.isEmpty,
                   childTitles.isEmpty {
                    Text("Block only")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.marker)
                    .frame(width: 4, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.body.weight(.semibold))
                    if let start = block.resolvedStartMinuteOfDay,
                       let end = block.resolvedEndMinuteOfDay {
                        Text("\(start.formattedTime)–\(end.formattedTime)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(.primary)
    }

    private func detailGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.accent)
            content()
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func taskOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum RoutineEditorMode: Hashable {
    case create
    case edit(UUID)

    var routineID: UUID? {
        guard case let .edit(id) = self else { return nil }
        return id
    }

    var title: String {
        switch self {
        case .create: "New Routine"
        case .edit: "Edit Routine"
        }
    }
}

struct RoutineEditorView: View {
    @Environment(SamoyedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: RoutineEditorMode

    @State private var routineTitle = "Morning Focus"
    @State private var blockTitle = "Focus Work"
    @State private var note = ""
    @State private var startMinute = 7 * 60 + 30
    @State private var endMinute = 10 * 60 + 30
    @State private var didLoad = false
    @State private var isConfirmingDelete = false

    private var isScheduleValid: Bool {
        startMinute < endMinute
    }

    private var canSave: Bool {
        !routineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isScheduleValid
    }

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Routine name", text: $routineTitle)
                    .textInputAutocapitalization(.words)
            }

            Section {
                DatePicker(
                    "Start",
                    selection: timeBinding(for: $startMinute),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "End",
                    selection: timeBinding(for: $endMinute),
                    displayedComponents: .hourAndMinute
                )
            } header: {
                Text("Schedule")
            } footer: {
                if !isScheduleValid {
                    Text("Start time must be earlier than end time.")
                        .foregroundStyle(.red)
                }
            }

            Section("Block") {
                TextField("Block title", text: $blockTitle)
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(2 ... 6)
            }

            Section("Details") {
                LabeledContent("Blocks", value: "1")
                LabeledContent("Reminders", value: "None")
                LabeledContent("Notes", value: note.isEmpty ? "Optional" : "Added")
            }

            Section("Actions") {
                Button(mode == .create ? "Create Routine" : "Save Changes") {
                    save()
                }
                .disabled(!canSave)

                if case .edit = mode {
                    Button("Delete Routine", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: mode.routineID) {
            loadRoutineIfNeeded()
        }
        .alert(
            "Delete \(routineTitle)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteRoutine()
            }
        } message: {
            Text("This removes the reusable definition. Today’s materialized routine is not changed.")
        }
    }

    private func loadRoutineIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let id = mode.routineID, let routine = store.savedTemplate(id: id) else { return }

        routineTitle = routine.title
        guard let root = routine.blocks.first(where: {
            $0.layerIndex == 0 && $0.parentTemplateBlockID == nil
        }) else { return }

        blockTitle = root.title
        note = root.note ?? ""
        if case let .absolute(start, requestedEnd) = root.timing {
            startMinute = start
            endMinute = requestedEnd ?? min(24 * 60 - 1, start + 60)
        }
    }

    private func save() {
        do {
            switch mode {
            case .create:
                _ = try store.createRoutine(
                    title: routineTitle,
                    blockTitle: blockTitle,
                    note: note,
                    startMinuteOfDay: startMinute,
                    endMinuteOfDay: endMinute
                )
            case let .edit(id):
                try store.updateRoutine(
                    id: id,
                    title: routineTitle,
                    blockTitle: blockTitle,
                    note: note,
                    startMinuteOfDay: startMinute,
                    endMinuteOfDay: endMinute
                )
            }
            dismiss()
        } catch {
            store.presentError(error)
        }
    }

    private func deleteRoutine() {
        guard let id = mode.routineID else { return }
        do {
            try store.deleteRoutine(id: id)
            dismiss()
        } catch {
            store.presentError(error)
        }
    }

    private func timeBinding(for minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { date(for: minute.wrappedValue) },
            set: { minute.wrappedValue = $0.minuteOfDay }
        )
    }

    private func date(for minute: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: minute, to: start) ?? start
    }
}

#Preview("Routines") {
    NavigationStack {
        RoutinesRootView()
    }
    .environment(PreviewSupport.store(tab: .library))
}

#Preview("New Routine") {
    NavigationStack {
        RoutineEditorView(mode: .create)
    }
    .environment(PreviewSupport.store(tab: .library))
}
