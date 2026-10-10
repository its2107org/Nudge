import AppIntents
import Foundation
import WidgetKit

// MARK: - Reminder as something Siri and Shortcuts can talk about

struct ReminderEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reminder"
    static var defaultQuery = ReminderQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct ReminderQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ReminderEntity] {
        ReminderStore.shared.reload()
        return ReminderStore.shared.reminders
            .filter { identifiers.contains($0.id) }
            .map { ReminderEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ReminderEntity] {
        ReminderStore.shared.reload()
        return ReminderStore.shared.reminders.map { ReminderEntity(id: $0.id, title: $0.title) }
    }
}

// MARK: - Siri and Shortcuts

struct MarkNextDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Done"
    static var description = IntentDescription("Ticks off a reminder. If you don't say which, it ticks off the one that's due.")

    @Parameter(title: "Reminder")
    var reminder: ReminderEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ReminderStore.shared
        store.reload()
        let target: Reminder?
        if let reminder {
            target = store.reminder(reminder.id)
        } else {
            target = store.mostUrgent
        }
        guard let target else {
            return .result(dialog: "You don't have any reminders set up yet.")
        }
        let updated = store.markDone(target.id)
        await AlertScheduler.rescheduleAll()
        WidgetCenter.shared.reloadAllTimelines()
        var message = "Done. \(target.title) is ticked off."
        if let updated {
            message += " Next one is \(updated.nextDue.formatted(.relative(presentation: .named)))."
            if let warning = updated.supplyWarning { message += " \(warning)." }
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct NextReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "When's My Next Reminder"
    static var description = IntentDescription("Tells you when your next reminder is due.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ReminderStore.shared
        store.reload()
        guard let next = store.mostUrgent else {
            return .result(dialog: "You don't have any reminders set up yet.")
        }
        let message: String
        if next.isDue {
            message = "\(next.title) is due now."
        } else {
            message = "\(next.title) is next, \(next.nextDue.formatted(date: .abbreviated, time: .shortened))."
        }
        var full = message
        if let site = next.suggestedSite { full += " Suggested spot: \(site)." }
        return .result(dialog: IntentDialog(stringLiteral: full))
    }
}

struct NudgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkNextDoneIntent(),
            phrases: [
                "Mark \(.applicationName) done",
                "Tick off \(.applicationName)",
                "Mark \(\.$reminder) done in \(.applicationName)",
                "I've done my \(\.$reminder) in \(.applicationName)",
            ],
            shortTitle: "Mark Done",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: NextReminderIntent(),
            phrases: [
                "When's my next \(.applicationName)",
                "What's next in \(.applicationName)",
            ],
            shortTitle: "What's Next",
            systemImageName: "calendar.badge.clock"
        )
    }
}
