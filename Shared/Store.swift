import Foundation
import Security
import WidgetKit

/// Saves everything in a keychain item shared by the app and its widget.
/// A shared keychain group needs no extra setup in the Apple developer portal,
/// unlike an App Group.
enum SharedStorage {
    private static let service = "Nudge"
    private static let account = "data"

    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "NudgeKeychainGroup") as? String
    }

    private static var fallbackURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("nudge.json")
    }

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group = accessGroup, !group.isEmpty, !group.contains("$(") {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    static func load() -> NudgeData {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let decoded = try? JSONDecoder().decode(NudgeData.self, from: data) {
            return decoded
        }
        if let data = try? Data(contentsOf: fallbackURL),
           let decoded = try? JSONDecoder().decode(NudgeData.self, from: data) {
            return decoded
        }
        return NudgeData()
    }

    static func save(_ value: NudgeData) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            try? data.write(to: fallbackURL, options: .atomic)
        }
    }
}

/// The one place that reads and changes reminders. Used by the app, widget buttons, Siri and alarms.
@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published private(set) var data: NudgeData

    private init() {
        data = SharedStorage.load()
    }

    var reminders: [Reminder] {
        data.reminders.sorted { a, b in
            if a.isPaused != b.isPaused { return !a.isPaused }
            return a.nextDue < b.nextDue
        }
    }

    var log: [LogEntry] { data.log.sorted { $0.doneDate > $1.doneDate } }

    func reload() {
        data = SharedStorage.load()
    }

    func reminder(_ id: UUID) -> Reminder? {
        data.reminders.first { $0.id == id }
    }

    /// The reminder that most needs doing: the most overdue, else the next one coming up.
    var mostUrgent: Reminder? {
        reminders.first { !$0.isPaused }
    }

    func upsert(_ reminder: Reminder) {
        if let index = data.reminders.firstIndex(where: { $0.id == reminder.id }) {
            data.reminders[index] = reminder
        } else {
            data.reminders.append(reminder)
        }
        persist()
    }

    func delete(_ id: UUID) {
        data.reminders.removeAll { $0.id == id }
        persist()
    }

    func deleteLog(_ id: UUID) {
        data.log.removeAll { $0.id == id }
        persist()
    }

    /// Marks a reminder as done. `restartFromNow` moves the rhythm so the next one is a full gap from now.
    @discardableResult
    func markDone(_ id: UUID, site: String? = nil, restartFromNow: Bool = false, at now: Date = Date()) -> Reminder? {
        reload()
        guard var reminder = reminder(id) else { return nil }
        let usedSite = site ?? reminder.suggestedSite
        data.log.append(LogEntry(
            reminderID: reminder.id,
            title: reminder.title,
            dueDate: reminder.nextDue,
            doneDate: now,
            site: usedSite,
            doseNote: reminder.doseNote.isEmpty ? nil : reminder.doseNote
        ))
        if data.log.count > 1000 {
            data.log.sort { $0.doneDate < $1.doneDate }
            data.log.removeFirst(data.log.count - 1000)
        }
        if let usedSite { reminder.lastSite = usedSite }
        if reminder.trackSupply {
            reminder.dosesLeft -= 1
            if reminder.dosesLeft < 0 { reminder.dosesLeft = reminder.dosesPerPen - 1 }
        }
        if restartFromNow, case .every(let hours) = reminder.schedule {
            reminder.nextDue = now.addingTimeInterval(hours * 3600)
        } else {
            reminder.nextDue = reminder.nextOccurrence(after: now)
        }
        upsert(reminder)
        return reminder
    }

    func startNewPen(_ id: UUID) {
        guard var reminder = reminder(id) else { return }
        reminder.dosesLeft = reminder.dosesPerPen
        upsert(reminder)
    }

    func setAlarmIDs(_ ids: [UUID], for id: UUID) {
        reload()
        guard var reminder = reminder(id) else { return }
        reminder.alarmIDs = ids
        if let index = data.reminders.firstIndex(where: { $0.id == id }) {
            data.reminders[index] = reminder
        }
        SharedStorage.save(data)
    }

    private func persist() {
        SharedStorage.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
