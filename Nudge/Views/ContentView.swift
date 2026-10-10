import SwiftUI
import AlarmKit
import UserNotifications

struct ContentView: View {
    var body: some View {
        TabView {
            RemindersView()
                .tabItem { Label("Reminders", systemImage: "bell.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
        }
        .tint(.orange)
    }
}

struct RemindersView: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var editing: Reminder?
    @State private var completing: Reminder?
    @State private var addingNew = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PermissionBanner()
                    if store.reminders.isEmpty {
                        EmptyStateView(
                            addMounjaro: { editing = Reminder.mounjaroPreset() },
                            addOther: { addingNew = true }
                        )
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        VStack(spacing: 16) {
                            ForEach(store.reminders) { reminder in
                                ReminderCard(reminder: reminder,
                                             onDone: { completing = reminder },
                                             onEdit: { editing = reminder })
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Nudge")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addingNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add reminder")
                }
            }
            .sheet(item: $editing) { reminder in
                EditReminderView(reminder: reminder, isNew: store.reminder(reminder.id) == nil)
            }
            .sheet(isPresented: $addingNew) {
                EditReminderView(reminder: Reminder(title: "", schedule: .weekdays(days: [2], hour: 9, minute: 0),
                                                    nextDue: Date().addingTimeInterval(3600)),
                                 isNew: true)
            }
            .sheet(item: $completing) { reminder in
                DoneSheet(reminder: reminder)
                    .presentationDetents([.medium, .large])
            }
            .refreshable { store.reload() }
        }
    }
}

struct EmptyStateView: View {
    var addMounjaro: () -> Void
    var addOther: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 54))
                .foregroundStyle(.orange)
            Text("No reminders yet")
                .font(.title2.bold())
            Text("Nudge rings like an alarm and keeps reminding you until you tap Done.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: addMounjaro) {
                Label("Add Mounjaro (twice a week)", systemImage: "syringe.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Add a different reminder", action: addOther)
        }
        .padding(24)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ReminderCard: View {
    let reminder: Reminder
    var onDone: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: reminder.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(reminder.isDue ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title).font(.headline)
                    Text(reminder.schedule.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Edit \(reminder.title)")
            }

            if reminder.isPaused {
                Label("Paused", systemImage: "pause.circle").foregroundStyle(.secondary)
            } else if reminder.isDue {
                Label("Due now (since \(reminder.nextDue.formatted(date: .omitted, time: .shortened)))", systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next: \(reminder.nextDue.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))")
                        .font(.subheadline.weight(.semibold))
                    Text(reminder.nextDue, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let site = reminder.suggestedSite {
                Label("Next spot: \(site)", systemImage: "figure.stand")
                    .font(.subheadline)
            }
            if reminder.trackSupply {
                Label("\(max(reminder.dosesLeft, 0)) of \(reminder.dosesPerPen) doses left in this pen", systemImage: "cross.vial.fill")
                    .font(.subheadline)
                if let warning = reminder.supplyWarning {
                    Text(warning).font(.subheadline.bold()).foregroundStyle(.orange)
                }
            }

            if !reminder.isPaused {
                Button(action: onDone) {
                    Label(reminder.isDue ? "Done" : "Done early", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(reminder.isDue ? .green : .gray)
                .controlSize(.large)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct DoneSheet: View {
    @EnvironmentObject private var store: ReminderStore
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder
    @State private var site: String = ""
    @State private var restartFromNow = false

    private var minutesLate: Int {
        Int(Date().timeIntervalSince(reminder.nextDue) / 60)
    }

    private var isEveryN: Bool {
        if case .every = reminder.schedule { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                if reminder.trackSites {
                    Section("Where did you inject?") {
                        Picker("Spot", selection: $site) {
                            ForEach(reminder.sites, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                if isEveryN && minutesLate > 60 {
                    Section {
                        Toggle("Count the next gap from now", isOn: $restartFromNow)
                    } footer: {
                        Text("You're \(ReminderSchedule.describe(hours: Double(minutesLate) / 60)) late. Turn this on to keep a full gap before the next one, or leave it off to stay on your usual days and times.")
                    }
                }
                if !reminder.isDue {
                    Section {
                        Text("This isn't due yet. Marking it done now moves you on to the next one.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(reminder.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.markDone(reminder.id, site: reminder.trackSites ? site : nil, restartFromNow: restartFromNow)
                        Task { await AlertScheduler.rescheduleAll() }
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { site = reminder.suggestedSite ?? reminder.sites.first ?? "" }
        }
    }
}

struct PermissionBanner: View {
    @State private var alarmsAllowed = true
    @State private var notificationsAllowed = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !alarmsAllowed || !notificationsAllowed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nudge can't ring properly yet", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                    Text("Tap below, then turn on \(missing) for Nudge.")
                        .font(.subheadline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, _ in Task { await refresh() } }
    }

    private var missing: String {
        switch (alarmsAllowed, notificationsAllowed) {
        case (false, false): return "Alarms and Notifications"
        case (false, true): return "Alarms"
        default: return "Notifications"
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized
        alarmsAllowed = AlarmManager.shared.authorizationState != .denied
    }
}
