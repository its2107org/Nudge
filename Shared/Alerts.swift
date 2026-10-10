import Foundation
import AlarmKit
import ActivityKit
import SwiftUI
import UserNotifications

/// Small piece of data attached to each alarm so the alarm screens know which reminder it is.
struct NudgeAlarmMetadata: AlarmMetadata {
    var reminderID: UUID
    var title: String
    var symbol: String
}

enum NudgeNotification {
    static let category = "NUDGE_REMINDER"
    static let doneAction = "NUDGE_DONE"
    static let reminderKey = "reminderID"
}

/// Sets up the alarm and the repeating notifications for every reminder.
/// Each reminder gets:
///  - a proper alarm at the due time (rings even on silent). If it's stopped without
///    being marked done, it rings again after the nag gap.
///  - a run of notifications every few minutes after that, as a back-up,
///    until it's marked done.
@MainActor
enum AlertScheduler {
    static let maxPendingNotifications = 60

    static func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: NudgeNotification.doneAction, title: "Done ✓", options: [])
        let category = UNNotificationCategory(identifier: NudgeNotification.category, actions: [done], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Rebuilds every alert from scratch so they always match the saved reminders.
    static func rescheduleAll() async {
        let store = ReminderStore.shared
        store.reload()
        let reminders = store.data.reminders
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let active = reminders.filter { !$0.isPaused }
        let perReminder = active.isEmpty ? 0 : max(4, maxPendingNotifications / active.count)

        // Remove alarms that no longer belong to a reminder.
        let knownIDs = Set(reminders.flatMap(\.alarmIDs))
        if let existing = try? AlarmManager.shared.alarms {
            for alarm in existing where !knownIDs.contains(alarm.id) {
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
        }

        for reminder in reminders {
            await schedule(reminder, notificationCount: perReminder)
        }
        try? await center.setBadgeCount(reminders.filter(\.isDue).count)
    }

    static func schedule(_ reminder: Reminder, notificationCount: Int) async {
        for id in reminder.alarmIDs { try? AlarmManager.shared.cancel(id: id) }
        var newAlarmIDs: [UUID] = []
        guard !reminder.isPaused else {
            ReminderStore.shared.setAlarmIDs([], for: reminder.id)
            return
        }

        let now = Date()
        let nag = TimeInterval(max(reminder.nagMinutes, 1) * 60)
        // If it's already overdue, start alerting again shortly.
        let firstAlert = reminder.nextDue > now ? reminder.nextDue : now.addingTimeInterval(30)

        var alarmScheduled = false
        if reminder.useAlarm, AlarmManager.shared.authorizationState == .authorized {
            if let id = await scheduleAlarm(for: reminder, at: firstAlert) {
                newAlarmIDs.append(id)
                alarmScheduled = true
            }
        }
        ReminderStore.shared.setAlarmIDs(newAlarmIDs, for: reminder.id)

        // Back-up notifications. With an alarm, they start one gap after it.
        let center = UNUserNotificationCenter.current()
        let start = alarmScheduled ? firstAlert.addingTimeInterval(nag) : firstAlert
        for index in 0..<notificationCount {
            let fireDate = start.addingTimeInterval(nag * Double(index))
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = index == 0 && !alarmScheduled ? "Time for your \(reminder.title)." : "Still to do: \(reminder.title). Tap Done once it's done."
            if let site = reminder.suggestedSite { content.body += " Suggested spot: \(site)." }
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = NudgeNotification.category
            content.userInfo = [NudgeNotification.reminderKey: reminder.id.uuidString]
            content.threadIdentifier = reminder.id.uuidString
            let interval = max(fireDate.timeIntervalSinceNow, 1)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: "\(reminder.id.uuidString)-\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Schedules one alarm. Called again by the alarm's Stop button if the reminder still isn't done.
    @discardableResult
    static func scheduleAlarm(for reminder: Reminder, at date: Date) async -> UUID? {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: reminder.title),
            secondaryButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark.circle.fill"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<NudgeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: NudgeAlarmMetadata(reminderID: reminder.id, title: reminder.title, symbol: reminder.symbol),
            tintColor: .orange
        )
        let id = UUID()
        let configuration = AlarmManager.AlarmConfiguration<NudgeAlarmMetadata>.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: AlarmStoppedIntent(reminderID: reminder.id.uuidString),
            secondaryIntent: MarkDoneIntent(reminderID: reminder.id.uuidString),
            sound: .default
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return id
        } catch {
            return nil
        }
    }
}
