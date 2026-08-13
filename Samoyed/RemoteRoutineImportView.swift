import SwiftUI

struct RemoteRoutineImportRequest: Identifiable, Sendable {
    let id = UUID()
    let remoteURL: URL
    let suggestedTitle: String?

    var resolvedTitle: String {
        if let suggestedTitle = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggestedTitle.isEmpty {
            return suggestedTitle
        }

        let filenameTitle = remoteURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filenameTitle.isEmpty ? "Imported Routine" : filenameTitle
    }
}

enum RoutineImportOrigin: Equatable {
    case remote(URL)
    case inlineLink
}

struct PendingRoutineImport: Identifiable {
    let id = UUID()
    let origin: RoutineImportOrigin
    let yaml: String
    let summary: PortableDayBlocksSummary
    let suggestedTitle: String
}

struct RemoteRoutineImportLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                Text("Downloading Routine Config")
                    .font(.headline)
                Text("The file will be validated before you can import it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Downloading and validating routine config")
    }
}

struct RoutineImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SamoyedStore.self) private var store

    let pendingImport: PendingRoutineImport

    @State private var routineTitle: String
    @State private var conflict: RemoteRoutineImportConflict?
    @State private var importErrorMessage: String?
    @State private var isImporting = false

    init(pendingImport: PendingRoutineImport) {
        self.pendingImport = pendingImport
        _routineTitle = State(initialValue: pendingImport.suggestedTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Routine name", text: $routineTitle)
                }

                Section("Source") {
                    switch pendingImport.origin {
                    case let .remote(sourceURL):
                        LabeledContent("Host", value: sourceURL.host ?? "Unknown")
                        LabeledContent("File", value: sourceFilename(for: sourceURL))
                    case .inlineLink:
                        LabeledContent("Method", value: "Embedded Link")
                        LabeledContent("Format", value: "YAML")
                    }
                }

                Section("Validated Config") {
                    LabeledContent("Blocks", value: "\(pendingImport.summary.totalBlockCount)")
                    LabeledContent("Base Blocks", value: "\(pendingImport.summary.baseBlockCount)")
                    LabeledContent("Checklist Items", value: "\(pendingImport.summary.taskCount)")
                }

                Section("Import Behavior") {
                    Text("Importing saves a local routine after confirmation. It does not change today’s materialized day or checklist completion.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importing…" : "Import") {
                        prepareImport()
                    }
                    .disabled(normalizedTitle.isEmpty || isImporting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Routine Already Exists",
            isPresented: Binding(
                get: { conflict != nil },
                set: { if !$0 { conflict = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let conflict {
                Button("Replace", role: .destructive) {
                    completeImport(title: conflict.title, replacingRoutineID: conflict.existingRoutineID)
                }
                Button("Keep Both") {
                    completeImport(title: uniqueRoutineTitle(from: conflict.title), replacingRoutineID: nil)
                }
            }
            Button("Cancel", role: .cancel) {
                conflict = nil
            }
        } message: {
            if let conflict {
                Text("A routine named \(conflict.title) is already in the local Library.")
            }
        }
        .alert(
            "Unable to Import Routine",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var normalizedTitle: String {
        routineTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceFilename(for sourceURL: URL) -> String {
        let filename = sourceURL.lastPathComponent
        return filename.isEmpty ? "Remote YAML" : filename
    }

    private func prepareImport() {
        let title = normalizedTitle
        guard !title.isEmpty else { return }

        if let existingRoutineID = store.routineID(titled: title) {
            conflict = RemoteRoutineImportConflict(
                title: title,
                existingRoutineID: existingRoutineID
            )
            return
        }

        completeImport(title: title, replacingRoutineID: nil)
    }

    private func completeImport(title: String, replacingRoutineID: UUID?) {
        isImporting = true
        defer { isImporting = false }

        do {
            _ = try store.importRoutineConfigYAML(
                pendingImport.yaml,
                title: title,
                replacingRoutineID: replacingRoutineID
            )
            conflict = nil
            dismiss()
            store.openLibrary(destination: .routines)
        } catch {
            importErrorMessage = error.localizedDescription
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
}

private struct RemoteRoutineImportConflict: Identifiable {
    let id = UUID()
    let title: String
    let existingRoutineID: UUID
}
