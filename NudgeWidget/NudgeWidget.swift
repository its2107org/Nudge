import WidgetKit
import SwiftUI
import AppIntents
import AlarmKit

@main
struct NudgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextReminderWidget()
        AlarmLiveActivity()
    }
}

// MARK: - Home screen and Lock Screen widget

struct ReminderEntry: TimelineEntry {
    let date: Date
    let reminders: [Reminder]
}

struct ReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReminderEntry {
        ReminderEntry(date: Date(), reminders: [Reminder.mounjaroPreset()])
    }

    func getSnapshot(in context: Context, completion: @escaping (ReminderEntry) -> Void) {
        let reminders = loadReminders()
        completion(ReminderEntry(date: Date(), reminders: reminders.isEmpty ? [Reminder.mounjaroPreset()] : reminders))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        let reminders = loadReminders()
        let now = Date()
        // A fresh entry at each upcoming due time, so the widget flips to "Due now" on time.
        var dates = [now]
        dates += reminders.map(\.nextDue).filter { $0 > now }.sorted().prefix(5)
        let entries = dates.map { ReminderEntry(date: $0, reminders: reminders) }
        let refresh = now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func loadReminders() -> [Reminder] {
        SharedStorage.load().reminders
            .filter { !$0.isPaused }
            .sorted { $0.nextDue < $1.nextDue }
    }
}

struct NextReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextReminder", provider: ReminderProvider()) { entry in
            ReminderWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next reminder")
        .description("Shows what's coming up, with a Done button when it's due.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct ReminderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReminderEntry

    private func isDue(_ reminder: Reminder) -> Bool { reminder.nextDue <= entry.date }

    var body: some View {
        if let first = entry.reminders.first {
            switch family {
            case .accessoryInline:
                if isDue(first) {
                    Text("\(first.title) due now")
                } else {
                    Text("\(first.title) \(first.nextDue, style: .relative)")
                }
            case .accessoryCircular:
                Button(intent: MarkDoneIntent(reminderID: first.id.uuidString)) {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Image(systemName: isDue(first) ? "checkmark" : first.symbol)
                                .font(.title3)
                            if !isDue(first) {
                                Text(shortCountdown(to: first.nextDue))
                                    .font(.caption2)
                                    .minimumScaleFactor(0.6)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isDue(first))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(first.title, systemImage: first.symbol).font(.headline)
                    if isDue(first) {
                        Button(intent: MarkDoneIntent(reminderID: first.id.uuidString)) {
                            Text("Due now · tap Done")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(first.nextDue.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        if let site = first.suggestedSite { Text(site).font(.caption) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.reminders.prefix(3)) { reminder in
                        ReminderRow(reminder: reminder, isDue: isDue(reminder))
                    }
                    Spacer(minLength: 0)
                }
            default:
                SmallReminderView(reminder: first, isDue: isDue(first))
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "bell.badge").font(.title2)
                Text("Open Nudge to add a reminder").font(.caption).multilineTextAlignment(.center)
            }
        }
    }

    private func shortCountdown(to date: Date) -> String {
        let hours = date.timeIntervalSince(entry.date) / 3600
        if hours >= 24 { return "\(Int(hours / 24))d" }
        if hours >= 1 { return "\(Int(hours))h" }
        return "\(max(Int(hours * 60), 1))m"
    }
}

struct SmallReminderView: View {
    let reminder: Reminder
    let isDue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: reminder.symbol)
                    .foregroundStyle(isDue ? .red : .orange)
                Text(reminder.title).font(.headline).lineLimit(1)
            }
            if isDue {
                Text("Due now").font(.title3.bold()).foregroundStyle(.red)
                Spacer(minLength: 0)
                Button(intent: MarkDoneIntent(reminderID: reminder.id.uuidString)) {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            } else {
                Text(reminder.nextDue.formatted(.dateTime.weekday(.wide)))
                    .font(.title3.bold())
                Text(reminder.nextDue.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                Spacer(minLength: 0)
                if let site = reminder.suggestedSite {
                    Text(site).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let warning = reminder.supplyWarning {
                    Text(warning).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let isDue: Bool

    var body: some View {
        HStack {
            Image(systemName: reminder.symbol)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(isDue ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 0) {
                Text(reminder.title).font(.subheadline.bold()).lineLimit(1)
                Text(isDue ? "Due now" : reminder.nextDue.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(isDue ? .red : .secondary)
            }
            Spacer()
            if isDue {
                Button(intent: MarkDoneIntent(reminderID: reminder.id.uuidString)) {
                    Image(systemName: "checkmark")
                }
                .tint(.green)
            }
        }
    }
}

// MARK: - Alarm screen while snoozing

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<NudgeAlarmMetadata>.self) { context in
            HStack {
                Image(systemName: context.attributes.metadata?.symbol ?? "bell.fill")
                    .foregroundStyle(.orange)
                Text(context.attributes.metadata?.title ?? "Reminder").font(.headline)
                Spacer()
                AlarmTimeText(state: context.state)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.metadata?.symbol ?? "bell.fill").foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.title ?? "Reminder").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmTimeText(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
            } compactTrailing: {
                AlarmTimeText(state: context.state).frame(maxWidth: 50)
            } minimal: {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
            }
        }
    }
}

struct AlarmTimeText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let info):
            Text(info.fireDate, style: .timer).monospacedDigit()
        case .paused:
            Text("Paused")
        case .alert:
            Text("Now")
        @unknown default:
            Text("")
        }
    }
}
