import SwiftUI
import UIKit

private enum NowSheet: String, Identifiable {
    case todayDifferent
    var id: String { rawValue }
}

struct NowRootView: View {
    @Environment(ThingStructStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: NowSheet?
    @State private var undoReferences: [TaskCompletionReference] = []
    @State private var undoExpiryTask: Task<Void, Never>?
    @State private var hapticTrigger = 0

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                RootScreenContainer(
                    isLoaded: store.isReady,
                    loadingTitle: "Loading Now",
                    loadingSystemImage: "clock",
                    loadingDescription: "Finding your current block.",
                    errorTitle: "Unable to Build Now",
                    retry: store.reload
                ) {
                    try store.nowScreenModel(at: context.date)
                } content: { model in
                    NowFocusContent(
                        model: model,
                        onComplete: complete,
                        onTodayDifferent: { sheet = .todayDifferent }
                    )
                }
            }
            .navigationTitle(LocalDay.today().nowNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .todayDifferent
                    } label: {
                        Label("Today is different", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: hapticTrigger)
        .overlay(alignment: .bottom) {
            if !undoReferences.isEmpty {
                UndoCompletionBanner(count: undoReferences.count, undo: undo)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .todayDifferent:
                TodayDifferentSheet(date: .today())
                    .environment(store)
            }
        }
        .task {
            store.recordNowVisible()
        }
        .onDisappear {
            undoExpiryTask?.cancel()
        }
    }

    private func complete(blockID: UUID, task: TaskItem) {
        do {
            guard let reference = try store.completeTask(
                on: .today(),
                blockID: blockID,
                taskID: task.id
            ) else { return }
            withAnimation(feedbackAnimation) {
                undoReferences.append(reference)
            }
            hapticTrigger += 1
            UIAccessibility.post(notification: .announcement, argument: "Completed \(task.title). Undo available.")
            scheduleUndoExpiry()
        } catch {
            store.presentError(error)
        }
    }

    private func undo() {
        do {
            try store.undoTaskCompletions(undoReferences)
            UIAccessibility.post(notification: .announcement, argument: "Completion undone.")
            undoExpiryTask?.cancel()
            withAnimation(feedbackAnimation) {
                undoReferences.removeAll()
            }
        } catch {
            store.presentError(error)
        }
    }

    private func scheduleUndoExpiry() {
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(feedbackAnimation) {
                undoReferences.removeAll()
            }
        }
    }

    private var feedbackAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 1)
    }
}

private struct NowFocusContent: View {
    let model: NowScreenModel
    let onComplete: (UUID, TaskItem) -> Void
    let onTodayDifferent: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NowHeroCard(model: model)

                if let focus = model.focusBlock,
                   let taskSourceBlockID = focus.taskSourceBlockID,
                   !focus.visibleTasks.isEmpty {
                    NowChecklistCard(
                        focus: focus,
                        blockID: taskSourceBlockID,
                        onComplete: onComplete
                    )
                }

                if let upcoming = model.upcomingBlock {
                    NowNextCard(upcoming: upcoming)
                }

                Button(action: onTodayDifferent) {
                    Label("Today is different", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("now-today-different")
            }
            .padding(16)
            .padding(.bottom, 72)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct NowHeroCard: View {
    let model: NowScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(statusLabel, systemImage: statusImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let focus = model.focusBlock {
                Text(focus.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Until \(focus.endMinuteOfDay.formattedTime)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                if let note = focus.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text(emptyTitle)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(emptyMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch model.focusState {
        case .active: "Now"
        case .noRoutine: "No routine"
        case .beforeFirstBlock: "Before your first block"
        case .openTime: "Open time"
        case .finished: "Today"
        }
    }

    private var statusImage: String {
        switch model.focusState {
        case .active: "scope"
        case .noRoutine: "calendar.badge.minus"
        case .beforeFirstBlock: "sunrise"
        case .openTime: "wind"
        case .finished: "checkmark.circle"
        }
    }

    private var emptyTitle: String {
        switch model.focusState {
        case .noRoutine: "Nothing is running today"
        case .beforeFirstBlock: "Your day has not started"
        case .openTime: "This time is yours"
        case .finished: "You are done for today"
        case .active: "Now"
        }
    }

    private var emptyMessage: String {
        switch model.focusState {
        case .noRoutine: "Choose a saved day type, or keep today open."
        case .beforeFirstBlock: "Your first block is ready when its time arrives."
        case .openTime: "No block needs your attention right now."
        case .finished: "There are no more scheduled blocks today."
        case .active: "Stay with the next clear action."
        }
    }
}

private struct NowChecklistCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let focus: NowFocusBlock
    let blockID: UUID
    let onComplete: (UUID, TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Checklist")
                        .font(.headline)
                    Text("\(focus.remainingTaskCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Checklist")
                        .font(.headline)
                    Spacer()
                    Text("\(focus.remainingTaskCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let taskSourceTitle = focus.taskSourceTitle, taskSourceTitle != focus.title {
                Text("From \(taskSourceTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(focus.visibleTasks) { task in
                Button {
                    onComplete(blockID, task)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        Text(task.title)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TaskCompletionButtonStyle())
                .accessibilityLabel("Mark \(task.title) complete")
            }

            if focus.remainingTaskCount > focus.visibleTasks.count {
                Text("+\(focus.remainingTaskCount - focus.visibleTasks.count) more in Today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct NowNextCard: View {
    let upcoming: NowUpcomingBlock

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(upcoming.title)
                    .font(.headline)
                Text(upcoming.transitionMinuteOfDay.formattedTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct UndoCompletionBanner: View {
    let count: Int
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(count == 1 ? "Completed" : "\(count) completed")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Undo", action: undo)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}

private struct TaskCompletionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("Now") {
    NowRootView()
        .environment(PreviewSupport.store(tab: .now))
}
