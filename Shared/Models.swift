import Foundation

/// How often a reminder comes round.
enum ReminderSchedule: Codable, Hashable {
    /// A fixed gap, e.g. every 84 hours (3½ days) for a twice-weekly injection.
    case every(hours: Double)
    /// Chosen days of the week at a set time. Weekdays use Calendar numbering (1 = Sunday).
    case weekdays(days: [Int], hour: Int, minute: Int)

    var summary: String {
        switch self {
        case .every(let hours):
            return "Every \(ReminderSchedule.describe(hours: hours))"
        case .weekdays(let days, let hour, let minute):
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = days.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let time = Calendar.current.date(from: comps).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            if names.count == 7 { return "Every day at \(time)" }
            return "\(names.joined(separator: ", ")) at \(time)"
        }
    }

    static func describe(hours: Double) -> String {
        let totalHours = Int(hours.rounded())
        let days = totalHours / 24
        let rest = totalHours % 24
        if days == 0 { return "\(rest) hour\(rest == 1 ? "" : "s")" }
        if rest == 0 { return days == 1 ? "day" : "\(days) days" }
        if rest == 12 { return "\(days)½ days" }
        return "\(days) day\(days == 1 ? "" : "s") \(rest) hour\(rest == 1 ? "" : "s")"
    }
}

struct Reminder: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String = "bell.fill"
    var schedule: ReminderSchedule
    /// When this reminder is next due. Stays in the past (overdue) until it is marked done.
    var nextDue: Date
    /// How many minutes between repeat alerts until it is marked done.
    var nagMinutes: Int = 5
    /// Ring like a proper alarm (sounds even on silent).
    var useAlarm: Bool = true
    var isPaused: Bool = false

    // Injection site rotation
    var trackSites: Bool = false
    var sites: [String] = Reminder.defaultSites
    var lastSite: String?

    // Pen / supply tracking
    var trackSupply: Bool = false
    var dosesPerPen: Int = 4
    var dosesLeft: Int = 4

    /// Free text such as "5 mg", saved with each log entry.
    var doseNote: String = ""

    /// AlarmKit alarms currently scheduled for this reminder.
    var alarmIDs: [UUID] = []

    static let defaultSites = ["Tummy (left)", "Tummy (right)", "Left thigh", "Right thigh", "Left arm", "Right arm"]

    var isDue: Bool { !isPaused && nextDue <= Date() }

    var suggestedSite: String? {
        guard trackSites, !sites.isEmpty else { return nil }
        guard let last = lastSite, let index = sites.firstIndex(of: last) else { return sites.first }
        return sites[(index + 1) % sites.count]
    }

    var supplyWarning: String? {
        guard trackSupply else { return nil }
        if dosesLeft <= 0 { return "Pen empty: start a new pen" }
        if dosesLeft == 1 { return "Last dose in this pen: reorder soon" }
        return nil
    }

    /// The first due date after `date` that keeps the regular rhythm.
    func nextOccurrence(after date: Date) -> Date {
        switch schedule {
        case .every(let hours):
            let step = max(hours, 0.25) * 3600
            var next = nextDue
            if next > date { next = next.addingTimeInterval(step) }
            while next <= date { next = next.addingTimeInterval(step) }
            return next
        case .weekdays(let days, let hour, let minute):
            let validDays = days.filter { (1...7).contains($0) }
            guard !validDays.isEmpty else { return date.addingTimeInterval(7 * 86400) }
            let calendar = Calendar.current
            let from = max(date, nextDue)
            var best: Date?
            for day in validDays {
                var comps = DateComponents()
                comps.weekday = day
                comps.hour = hour
                comps.minute = minute
                if let candidate = calendar.nextDate(after: from, matching: comps, matchingPolicy: .nextTime) {
                    if best == nil || candidate < best! { best = candidate }
                }
            }
            return best ?? date.addingTimeInterval(7 * 86400)
        }
    }

    static func mounjaroPreset() -> Reminder {
        // Default first dose: next Sunday at 8am, then every 3½ days (Sun 8am, Wed 8pm).
        var comps = DateComponents()
        comps.weekday = 1
        comps.hour = 8
        comps.minute = 0
        let first = Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86400)
        return Reminder(
            title: "Mounjaro",
            symbol: "syringe.fill",
            schedule: .every(hours: 84),
            nextDue: first,
            nagMinutes: 5,
            useAlarm: true,
            trackSites: true,
            trackSupply: true,
            dosesPerPen: 4,
            dosesLeft: 4
        )
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var reminderID: UUID
    var title: String
    var dueDate: Date
    var doneDate: Date
    var site: String?
    var doseNote: String?
}

struct NudgeData: Codable {
    var reminders: [Reminder] = []
    var log: [LogEntry] = []
}
