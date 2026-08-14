import SwiftUI

enum LibraryDestination: Hashable {
    case routines
    case usualWeek
    case suggestions
    case planner
    case appearance
    case routineFiles
}

struct LibraryRootView: View {
    @Environment(SamoyedStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.libraryNavigationPath) {
            Group {
                if !store.isLoaded {
                    ScreenLoadingView(
                        title: "Loading Routines",
                        systemImage: "square.stack.3d.up",
                        description: "Preparing today’s routine choice and your local routine library."
                    )
                } else {
                    RootScreenContainer(
                        isLoaded: true,
                        loadingTitle: "Loading Routines",
                        loadingSystemImage: "square.stack.3d.up",
                        loadingDescription: "Preparing today’s routine choice and your local routine library.",
                        errorTitle: "Unable to Load Library",
                        retry: store.reload,
                        load: { try store.templatesScreenModel() }
                    ) { model in
                        LibraryContent(model: model)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink(value: LibraryDestination.appearance) {
                            Label("Appearance", systemImage: "paintpalette")
                        }
                        NavigationLink(value: LibraryDestination.routineFiles) {
                            Label("Routine Files", systemImage: "arrow.up.arrow.down")
                        }
                        NavigationLink(value: LibraryDestination.planner) {
                            Label("About Planner", systemImage: "sparkles")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("library-more")
                }
            }
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .routines:
                    RoutinesRootView()
                case .usualWeek:
                    UsualWeekView()
                case .suggestions:
                    SuggestionsInboxView()
                case .planner:
                    PlannerView()
                case .appearance:
                    LibraryAppearanceView()
                case .routineFiles:
                    LibraryImportExportView()
                }
            }
        }
    }
}

private struct LibraryContent: View {
    @Environment(SamoyedStore.self) private var store

    let model: TemplatesScreenModel

    var body: some View {
        List {
            if model.savedTemplates.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Routines", systemImage: "square.and.arrow.down")
                    } description: {
                        Text("Import a Routine Config File or create one with ChatGPT.")
                    } actions: {
                        Button {
                            store.libraryNavigationPath.append(.routineFiles)
                        } label: {
                            Label("Import Routine Config File", systemImage: "square.and.arrow.down")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
                .listRowBackground(Color.clear)
            } else {
                todaySection
                suggestionsSection
                routinesSection
                toolsSection
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var todaySection: some View {
        Section("Today") {
            if let current = model.todayChooser.currentSelection {
                NavigationLink {
                    RoutineDetailView(routineID: current.id)
                } label: {
                    LibraryRoutineRow(
                        routine: current,
                        subtitle: ["Running", current.timeRangeText].compactMap { $0 }.joined(separator: " · "),
                        showsSelection: true
                    )
                }
                .accessibilityIdentifier("library-current-routine")
            } else {
                NavigationLink(value: LibraryDestination.routines) {
                    Label("Choose Today’s Routine", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let pending = store.document.suggestions.filter { $0.lifecycleState == .pending }
        if !pending.isEmpty {
            Section("Suggestions") {
                NavigationLink(value: LibraryDestination.suggestions) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            pending.contains(where: { $0.kind == .dailyPlan })
                                ? "Tomorrow’s Plan"
                                : "Routine Improvements",
                            systemImage: "sparkles"
                        )
                        Text("\(pending.reduce(0) { $0 + max(1, $1.changes.count) }) changes · Ready to review")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("library-suggestions")
            }
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        Section("Routines") {
            ForEach(model.savedTemplates.filter { !$0.isCurrentForToday }.prefix(3)) { routine in
                NavigationLink {
                    RoutineDetailView(routineID: routine.id)
                } label: {
                    LibraryRoutineRow(
                        routine: routine,
                        subtitle: routine.timeRangeText ?? "Reusable routine",
                        showsSelection: false
                    )
                }
            }

            NavigationLink(value: LibraryDestination.routines) {
                Label("All Routines", systemImage: "square.stack.3d.up")
            }

            NavigationLink(value: LibraryDestination.usualWeek) {
                Label("Usual Week", systemImage: "calendar")
            }
        }
    }

    @ViewBuilder
    private var toolsSection: some View {
        Section("Planner & Files") {
            NavigationLink(value: LibraryDestination.planner) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Planner", systemImage: "sparkles")
                    Text(plannerStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("library-planner")
            NavigationLink(value: LibraryDestination.routineFiles) {
                Label("Routine Files", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    private var plannerStatusText: String {
        switch store.document.plannerSettings.connectionState {
        case .disconnected: "Not Connected"
        case .connected: "Connected"
        case .unavailable: "Unavailable · routines continue locally"
        case .needsAttention: "Needs Attention"
        }
    }
}

private struct LibraryRoutineRow: View {
    let routine: TemplateCandidateSummary
    let subtitle: String
    let showsSelection: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.body)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsSelection {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected for today")
            }
        }
    }
}

struct LibraryAppearanceView: View {
    @Environment(SamoyedStore.self) private var store

    var body: some View {
        List {
            Section("Tint Presets") {
                ForEach(AppTintPreset.allCases) { preset in
                    Button {
                        store.applyTintPreset(preset)
                    } label: {
                        TintPresetRow(
                            preset: preset,
                            isSelected: store.tintPreset == preset
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance-\(preset.rawValue)")
                    .accessibilityAddTraits(store.tintPreset == preset ? [.isSelected] : [])
                }
            }

            Section {
                LabeledContent("Global Accent", value: store.tintPreset.title)
                LabeledContent("Blank Blocks", value: "Neutral")
            } header: {
                Text("Behavior")
            } footer: {
                Text("The selected tint updates Now, Today, Library, widgets, and Live Activities while blank blocks remain neutral.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TintPresetRow: View {
    let preset: AppTintPreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            TintPresetSwatch(preset: preset)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(preset.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct TintPresetSwatch: View {
    let preset: AppTintPreset

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .leading) {
                ForEach(Array((0 ..< 4).reversed()), id: \.self) { layer in
                    let style = LayerVisualStyle.forBlock(
                        layerIndex: layer,
                        isBlank: false,
                        preset: preset
                    )

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(style.strongSurface)
                        .frame(width: 30, height: 21)
                        .offset(x: CGFloat(layer) * 7)
                }
            }
            .frame(width: 55, height: 25, alignment: .leading)

            Circle()
                .fill(preset.tintColor)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                }
        }
        .frame(width: 62, height: 34)
        .accessibilityHidden(true)
    }
}

#Preview("Library") {
    LibraryRootView()
        .environment(PreviewSupport.store(tab: .library))
}

#Preview("Appearance") {
    NavigationStack {
        LibraryAppearanceView()
    }
    .environment(PreviewSupport.store(tab: .library, tintPreset: .ocean))
}
