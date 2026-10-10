import AppIntents
import Foundation
import WidgetKit
import AlarmKit

// MARK: - Buttons on the widget and the alarm

/// "Done" from the widget, the alarm screen or a notification.
/// It's a LiveActivityIntent so it always runs inside the app, which owns the alarms.
struct MarkDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Reminder Done"
    static var isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: reminderID) {
            ReminderStore.shared.markDone(id)
            await AlertScheduler.rescheduleAll()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Runs when the alarm's Stop button is pressed. If the reminder still isn't done,
/// the alarm is set to ring again after the nag gap.
struct AlarmStoppedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Alarm Stopped"
    static var isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = ReminderStore.shared
        store.reload()
        if let id = UUID(uuidString: reminderID), let reminder = store.reminder(id), reminder.isDue {
            let next = Date().addingTimeInterval(TimeInterval(max(reminder.nagMinutes, 1) * 60))
            if let alarmID = await AlertScheduler.scheduleAlarm(for: reminder, at: next) {
                store.setAlarmIDs(reminder.alarmIDs + [alarmID], for: id)
            }
        }
        return .result()
    }
}

