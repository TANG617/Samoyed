import SwiftUI

struct TodayDifferentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThingStructStore.self) private var store
    let date: LocalDay

    @State private var pendingTemplateID: UUID??
    @State private var startedAt = Date.now
    @State private var didFinish = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(nil)
                    } label: {
                        TodayDifferentRow(
                            title: "No routine today",
                            subtitle: "Keep today open without changing your usual week.",
                            systemImage: "calendar.badge.minus",
                            isSelected: currentTemplateID == nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-no-routine")
                }

                Section("Saved Day Types") {
                    if store.savedTemplates.isEmpty {
                        ContentUnavailableView(
                            "No Day Types",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Create one in Library first.")
                        )
                    } else {
                        ForEach(store.savedTemplates.sorted(by: templateSort)) { template in
                            Button {
                                choose(template.id)
                            } label: {
                                TodayDifferentRow(
                                    title: template.title,
                                    subtitle: scheduleSummary(for: template),
                                    systemImage: "square.stack.3d.up",
                                    isSelected: currentTemplateID == template.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Today is different")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        finish(outcome: "cancelled", variant: nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Replace today's plan?",
            isPresented: Binding(
                get: { pendingTemplateID != nil },
                set: { if !$0 { pendingTemplateID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace Today", role: .destructive) {
                guard let wrapped = pendingTemplateID else { return }
                apply(wrapped, forceReplace: true)
            }
            Button("Cancel", role: .cancel) {
                pendingTemplateID = nil
            }
        } message: {
            Text("Completed checklist items and today-only changes will be replaced. Your saved day types will not change.")
        }
        .onAppear {
            startedAt = .now
            store.recordValidationEvent(.todayDifferentOpened, outcome: "opened", at: startedAt)
        }
        .onDisappear {
            if !didFinish {
                finish(outcome: "dismissed", variant: nil)
            }
        }
    }

    private var currentTemplateID: UUID? {
        store.document.daySelection(for: date)?.selectedTemplateID
            ?? store.document.dayPlan(for: date)?.sourceSavedTemplateID
    }

    private func choose(_ templateID: UUID?) {
        apply(templateID, forceReplace: false)
    }

    private func apply(_ templateID: UUID?, forceReplace: Bool) {
        do {
            let result = try store.chooseTemplate(
                for: date,
                templateID: templateID,
                source: templateID == nil ? .noTemplate : .pickedTemplate,
                forceReplace: forceReplace
            )
            switch result {
            case .applied:
                finish(outcome: "saved", variant: templateID == nil ? "no-routine" : "saved-day-type")
                dismiss()
            case .requiresConfirmation:
                pendingTemplateID = .some(templateID)
            }
        } catch {
            store.presentError(error)
        }
    }

    private func finish(outcome: String, variant: String?) {
        guard !didFinish else { return }
        didFinish = true
        store.recordValidationEvent(
            .todayDifferentCompleted,
            outcome: outcome,
            variant: variant,
            durationMilliseconds: Int(Date.now.timeIntervalSince(startedAt) * 1_000)
        )
    }

    private func scheduleSummary(for template: SavedDayTemplate) -> String {
        let count = template.blocks.filter { $0.layerIndex == 0 }.count
        return count == 1 ? "1 block" : "\(count) blocks"
    }

    private func templateSort(_ lhs: SavedDayTemplate, _ rhs: SavedDayTemplate) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

// Kept as a compatibility wrapper for legacy call sites and previews.
struct TodayTemplateChooserView: View {
    let date: LocalDay

    var body: some View {
        TodayDifferentSheet(date: date)
    }
}

private struct TodayDifferentRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

#Preview("Today Different") {
    TodayDifferentSheet(date: .today())
        .environment(PreviewSupport.store())
}
