import Foundation

enum ReminderPreset: String, CaseIterable, Identifiable {
    case atStart
    case fiveMinutesBefore
    case tenMinutesBefore
    case fifteenMinutesBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atStart:
            return "At start"
        case .fiveMinutesBefore:
            return "5 min before"
        case .tenMinutesBefore:
            return "10 min before"
        case .fifteenMinutesBefore:
            return "15 min before"
        }
    }

    var rule: ReminderRule {
        switch self {
        case .atStart:
            return ReminderRule(triggerMode: .atStart, offsetMinutes: 0)
        case .fiveMinutesBefore:
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: 5)
        case .tenMinutesBefore:
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: 10)
        case .fifteenMinutesBefore:
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: 15)
        }
    }

    init?(rule: ReminderRule) {
        switch (rule.triggerMode, rule.offsetMinutes) {
        case (.atStart, _):
            self = .atStart
        case (.beforeStart, 5):
            self = .fiveMinutesBefore
        case (.beforeStart, 10):
            self = .tenMinutesBefore
        case (.beforeStart, 15):
            self = .fifteenMinutesBefore
        default:
            return nil
        }
    }
}
