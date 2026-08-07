import SwiftUI

enum LibraryDestination: Hashable {
    case templates
    case importExport
    case settings
}

private enum LibrarySheetDestination: Identifiable {
    case simple(SimpleDayTypeDraft)
    case advanced(UUID)
    case validationExport(URL)

    var id: String {
        switch self {
        case let .simple(draft): "simple-\(draft.templateID?.uuidString ?? "new")"
        case let .advanced(id): "advanced-\(id.uuidString)"
        case let .validationExport(url): "export-\(url.path())"
        }
    }
}

struct LibraryRootView: View {
    @Environment(ThingStructStore.self) private var store
    @State private var sheet: LibrarySheetDestination?
    @State private var templateToDelete: SavedDayTemplate?
    @State private var showingClearValidationConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Day Types") {
                    if store.savedTemplates.isEmpty {
                        ContentUnavailableView(
                            "No Day Types",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Create one reusable shape for a kind of day.")
                        )
                        Button {
                            sheet = .simple(.newDayType)
                        } label: {
                            Label("Create Day Type", systemImage: "plus")
                        }
                    } else {
                        ForEach(sortedTemplates) { template in
                            Button {
                                edit(template)
                            } label: {
                                DayTypeRow(
                                    template: template,
                                    weekdays: store.assignedWeekdays(for: template.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    templateToDelete = template
                                }
                            }
                        }
                    }
                }

                Section("Usual Week") {
                    ForEach(Weekday.mondayFirst) { weekday in
                        Picker(
                            weekday.fullName,
                            selection: Binding(
                                get: { store.assignedTemplateID(for: weekday) },
                                set: { store.assignWeekday(weekday, to: $0) }
                            )
                        ) {
                            Text("None").tag(UUID?.none)
                            ForEach(sortedTemplates) { template in
                                Text(template.title).tag(Optional(template.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .simple(.newDayType)
                    } label: {
                        Label("New Day Type", systemImage: "plus")
                    }
                }

                if ValidationRuntime.isEnabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Export Validation Log", systemImage: "square.and.arrow.up") {
                                Task {
                                    if let url = await store.validationExportURL() {
                                        sheet = .validationExport(url)
                                    } else {
                                        store.presentErrorMessage("No validation events have been recorded yet.")
                                    }
                                }
                            }
                            Button("Clear Validation Log", systemImage: "trash", role: .destructive) {
                                showingClearValidationConfirmation = true
                            }
                        } label: {
                            Label("Validation", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case let .simple(draft):
                SimpleDayTypeEditorSheet(draft: draft)
                    .environment(store)

            case let .advanced(templateID):
                if let template = store.savedTemplate(id: templateID) {
                    TemplateEditorSheet(
                        template: template,
                        assignedWeekdays: store.assignedWeekdays(for: templateID),
                        occupiedWeekdays: store.occupiedWeekdays(excluding: templateID),
                        onSave: { title, blocks, weekdays in
                            try store.saveEditedTemplate(
                                templateID,
                                title: title,
                                blocks: blocks,
                                assignedWeekdays: weekdays
                            )
                        },
                        onDelete: { store.deleteSavedTemplate(templateID) }
                    )
                }

            case let .validationExport(url):
                NavigationStack {
                    VStack(spacing: 18) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("Validation Log")
                            .font(.title2.bold())
                        Text("This JSONL file contains anonymous product events only.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        ShareLink(item: url) {
                            Label("Share Log", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .navigationTitle("Export")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
        }
        .confirmationDialog(
            "Delete this day type?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Day Type", role: .destructive) {
                if let templateToDelete {
                    store.deleteSavedTemplate(templateToDelete.id)
                    store.recordValidationEvent(
                        .dayTypeEditCompleted,
                        outcome: "deleted",
                        variant: templateToDelete.isSimpleDayType ? "simple" : "advanced"
                    )
                }
                templateToDelete = nil
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: {
            Text("Existing days remain unchanged. Usual-week assignments for this day type will be removed.")
        }
        .confirmationDialog(
            "Clear the validation log?",
            isPresented: $showingClearValidationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) {
                Task { await store.clearValidationLog() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sortedTemplates: [SavedDayTemplate] {
        store.savedTemplates.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func edit(_ template: SavedDayTemplate) {
        if let draft = SimpleDayTypeDraft(
            template: template,
            assignedWeekdays: store.assignedWeekdays(for: template.id)
        ) {
            sheet = .simple(draft)
        } else {
            sheet = .advanced(template.id)
        }
    }
}

private struct DayTypeRow: View {
    let template: SavedDayTemplate
    let weekdays: Set<Weekday>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: template.isSimpleDayType ? "square.stack.3d.up" : "square.3.layers.3d")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(template.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !template.isSimpleDayType {
                        Text("Advanced")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var summary: String {
        let orderedDays = Weekday.mondayFirst.filter(weekdays.contains).map(\.shortName)
        let schedule = orderedDays.isEmpty ? "No usual days" : orderedDays.joined(separator: ", ")
        let blockCount = template.blocks.filter { $0.layerIndex == 0 }.count
        return "\(blockCount) \(blockCount == 1 ? "block" : "blocks") · \(schedule)"
    }
}

#Preview("Library") {
    LibraryRootView()
        .environment(PreviewSupport.store(tab: .library))
}
