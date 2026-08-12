import SwiftUI
import UniformTypeIdentifiers

struct LibraryImportExportView: View {
    @Environment(SamoyedStore.self) private var store

    @State private var preparedExportFile: SharedExportFile?
    @State private var sharedExportCleanupURL: URL?
    @State private var isShowingImporter = false
    @State private var pendingImport: PendingRoutineImport?
    @State private var importRoutineTitle = ""
    @State private var selectedExportRoutineID: UUID?
    @State private var pendingConflict: PendingRoutineImportConflict?

    var body: some View {
        List {
            Section("Import") {
                Button {
                    isShowingImporter = true
                } label: {
                    Label("Import Routine Config File", systemImage: "square.and.arrow.down")
                }
                .disabled(!store.isLoaded)
            }

            Section("Export") {
                if store.savedTemplates.isEmpty {
                    Text("No routines are available to export.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Routine", selection: $selectedExportRoutineID) {
                        Text("Choose Routine").tag(UUID?.none)
                        ForEach(store.savedTemplates) { routine in
                            Text(routine.title).tag(UUID?.some(routine.id))
                        }
                    }

                    if let preparedExportFile {
                        ShareLink(
                            item: preparedExportFile.url,
                            preview: SharePreview(
                                preparedExportFile.title,
                                image: Image(systemName: "doc.text")
                            )
                        ) {
                            Label("Export Selected Routine", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {} label: {
                            Label("Export Selected Routine", systemImage: "square.and.arrow.up")
                        }
                        .disabled(true)
                    }
                }
            }

            Section("Format") {
                formatRow(
                    title: "Routine Config File",
                    subtitle: "Adds reusable routines to the local Library."
                )
                formatRow(
                    title: "YAML",
                    subtitle: "Titles, notes, tasks, timing, and nesting."
                )
            }
        }
        .navigationTitle("Routine Config Files")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingImport) { pendingImport in
            RoutineImportPreviewSheet(
                pendingImport: pendingImport,
                routineTitle: $importRoutineTitle,
                onCancel: {
                    self.pendingImport = nil
                },
                onImport: performPendingImport
            )
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.yaml, .plainText]
        ) { result in
            handleImportSelection(result)
        }
        .confirmationDialog(
            "Routine Already Exists",
            isPresented: Binding(
                get: { pendingConflict != nil },
                set: { if !$0 { pendingConflict = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let conflict = pendingConflict {
                Button("Replace", role: .destructive) {
                    completeImport(
                        conflict.pendingImport,
                        title: conflict.title,
                        replacingRoutineID: conflict.existingRoutineID
                    )
                }
                Button("Keep Both") {
                    completeImport(
                        conflict.pendingImport,
                        title: uniqueRoutineTitle(from: conflict.title),
                        replacingRoutineID: nil
                    )
                }
            }
            Button("Cancel", role: .cancel) {
                pendingConflict = nil
            }
        } message: {
            if let pendingConflict {
                Text("A routine named \(pendingConflict.title) is already in the Library.")
            }
        }
        .task {
            if selectedExportRoutineID == nil {
                selectedExportRoutineID = store.savedTemplates.first?.id
            }
            prepareExport()
        }
        .onChange(of: selectedExportRoutineID) { _, _ in
            prepareExport()
        }
        .onDisappear(perform: cleanupSharedExportFile)
    }

    private func prepareExport() {
        cleanupSharedExportFile()
        do {
            guard let selectedExportRoutineID else { return }
            let yaml = try store.exportRoutineConfigYAML(templateID: selectedExportRoutineID)
            let title = store.savedTemplate(id: selectedExportRoutineID)?.title ?? "routine"
            preparedExportFile = try makeSharedExportFile(yaml: yaml, routineTitle: title)
        } catch {
            store.presentError(error)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let yaml = try loadText(from: url)
            let summary = try store.previewRoutineConfigImport(yaml)
            importRoutineTitle = routineTitle(from: url)
            pendingImport = PendingRoutineImport(
                sourceFilename: url.lastPathComponent,
                yaml: yaml,
                summary: summary
            )
        } catch {
            store.presentError(error)
        }
    }

    private func performPendingImport() {
        guard let pendingImport else { return }
        let title = importRoutineTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingRoutineID = store.routineID(titled: title) {
            self.pendingImport = nil
            pendingConflict = PendingRoutineImportConflict(
                pendingImport: pendingImport,
                title: title,
                existingRoutineID: existingRoutineID
            )
            return
        }

        completeImport(pendingImport, title: title, replacingRoutineID: nil)
    }

    private func completeImport(
        _ pendingImport: PendingRoutineImport,
        title: String,
        replacingRoutineID: UUID?
    ) {

        do {
            let routineID = try store.importRoutineConfigYAML(
                pendingImport.yaml,
                title: title,
                replacingRoutineID: replacingRoutineID
            )
            selectedExportRoutineID = routineID
            self.pendingImport = nil
            pendingConflict = nil
            importRoutineTitle = ""
        } catch {
            store.presentError(error)
        }
    }

    private func uniqueRoutineTitle(from title: String) -> String {
        var suffix = 2
        var candidate = "\(title) \(suffix)"
        while store.routineID(titled: candidate) != nil {
            suffix += 1
            candidate = "\(title) \(suffix)"
        }
        return candidate
    }

    private func formatRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadText(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private func routineTitle(from url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Imported Routine" : title
    }

    private func makeSharedExportFile(yaml: String, routineTitle: String) throws -> SharedExportFile {
        let filename = "samoyed-routine-\(safeFilenameStem(routineTitle)).yml"
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SamoyedExports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileURL = directory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: filename)
        let exportDirectory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        try Data(yaml.utf8).write(to: fileURL, options: .atomic)
        sharedExportCleanupURL = exportDirectory
        return SharedExportFile(url: fileURL, title: routineTitle)
    }

    private func safeFilenameStem(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let filteredScalars = normalized.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let stem = String(filteredScalars)
            .split(separator: "-")
            .joined(separator: "-")
        return stem.isEmpty ? "routine" : stem
    }

    private func cleanupSharedExportFile() {
        if let sharedExportCleanupURL {
            try? FileManager.default.removeItem(at: sharedExportCleanupURL)
        }
        sharedExportCleanupURL = nil
        preparedExportFile = nil
    }
}

private struct PendingRoutineImport: Identifiable {
    let id = UUID()
    let sourceFilename: String
    let yaml: String
    let summary: PortableDayBlocksSummary
}

private struct PendingRoutineImportConflict: Identifiable {
    let id = UUID()
    let pendingImport: PendingRoutineImport
    let title: String
    let existingRoutineID: UUID
}

private struct RoutineImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pendingImport: PendingRoutineImport
    @Binding var routineTitle: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Routine name", text: $routineTitle)
                }

                Section("Config File") {
                    LabeledContent("Filename", value: pendingImport.sourceFilename)
                    LabeledContent("Blocks", value: "\(pendingImport.summary.totalBlockCount)")
                    LabeledContent("Base Blocks", value: "\(pendingImport.summary.baseBlockCount)")
                    LabeledContent("Checklist Items", value: "\(pendingImport.summary.taskCount)")
                }

                Section("Import Behavior") {
                    Text("Importing adds a reusable routine to the local library. It does not change today’s materialized day or checklist completion.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport()
                    }
                    .disabled(routineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SharedExportFile: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

#Preview("Library Import & Export") {
    NavigationStack {
        LibraryImportExportView()
    }
    .environment(PreviewSupport.store(tab: .library))
}
