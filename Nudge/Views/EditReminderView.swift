import SwiftUI

struct EditReminderView: View {
    @EnvironmentObject private var store: ReminderStore
    @Environment(\.dismiss) private var dismiss

    @State var reminder: Reminder
    let isNew: Bool

    @State private var scheduleKind: Kind = .every
    @State private var everyDays = 3
    @State private var everyHours = 12
    @State private var weekdays: Set<Int> = [2]
    @State private var weekdayTime = Date()
    @State private var sitesText = ""
    @State private var confirmDelete = false

    enum Kind: String, CaseIterable, Identifiable {
        case every = "Every few days"
        case weekdays = "On set days"
        var id: String { rawValue }
    }

    static let symbols = ["syringe.fill", "pills.fill", "cross.vial.fill", "heart.fill", "drop.fill",
                          "bell.fill", "calendar", "trash.fill", "leaf.fill", "pawprint.fill",
                          "creditcard.fill", "house.fill"]
    static let nagChoices = [1, 2, 5, 10, 15, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it?") {
                    TextField("Name, e.g. Mounjaro", text: $reminder.title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.symbols, id: \.self) { symbol in
                                Button {
                                    reminder.symbol = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(reminder.symbol == symbol ? .white : .primary)
                                        .background(reminder.symbol == symbol ? Color.orange : Color.gray.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section {
                    Picker("Repeats", selection: $scheduleKind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if scheduleKind == .every {
                        Stepper("Every \(everyDays) day\(everyDays == 1 ? "" : "s")", value: $everyDays, in: 0...60)
                        Stepper("and \(everyHours) hour\(everyHours == 1 ? "" : "s")", value: $everyHours, in: 0...23)
                        DatePicker("Next one due", selection: $reminder.nextDue)
                    } else {
                        WeekdayPicker(selection: $weekdays)
                        DatePicker("Time", selection: $weekdayTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("When?")
                } footer: {
                    if scheduleKind == .every {
                        Text("For twice a week, choose 3 days and 12 hours. Set when the next one is due, and Nudge keeps that rhythm, for example Sunday 8am, then Wednesday 8pm.")
                    }
                }

                Section {
                    Toggle("Ring like an alarm", isOn: $reminder.useAlarm)
                    Picker("Remind again every", selection: $reminder.nagMinutes) {
                        ForEach(Self.nagChoices, id: \.self) { Text("\($0) min").tag($0) }
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("The alarm sounds even when your phone is on silent. Nudge keeps reminding you until you tap Done.")
                }

                Section {
                    Toggle("Suggest where to inject", isOn: $reminder.trackSites)
                    if reminder.trackSites {
                        TextField("Spots, one per line", text: $sitesText, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    Toggle("Count doses left in pen", isOn: $reminder.trackSupply)
                    if reminder.trackSupply {
                        Stepper("Doses per pen: \(reminder.dosesPerPen)", value: $reminder.dosesPerPen, in: 1...20)
                        Stepper("Doses left now: \(reminder.dosesLeft)", value: $reminder.dosesLeft, in: 0...20)
                    }
                    TextField("Current dose, e.g. 5 mg (optional)", text: $reminder.doseNote)
                } header: {
                    Text("Injection extras")
                }

                Section {
                    Toggle("Pause this reminder", isOn: $reminder.isPaused)
                    if !isNew {
                        Button("Delete reminder", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(reminder.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(reminder.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(reminder.id)
                    Task { await AlertScheduler.rescheduleAll() }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        sitesText = reminder.sites.joined(separator: "\n")
        switch reminder.schedule {
        case .every(let hours):
            scheduleKind = .every
            let total = Int(hours.rounded())
            everyDays = total / 24
            everyHours = total % 24
        case .weekdays(let days, let hour, let minute):
            scheduleKind = .weekdays
            weekdays = Set(days)
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            weekdayTime = Calendar.current.date(from: comps) ?? Date()
        }
    }

    private func save() {
        reminder.title = reminder.title.trimmingCharacters(in: .whitespaces)
        let sites = sitesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        reminder.sites = sites.isEmpty ? Reminder.defaultSites : sites
        if reminder.dosesLeft > reminder.dosesPerPen { reminder.dosesLeft = reminder.dosesPerPen }

        switch scheduleKind {
        case .every:
            let hours = Double(max(everyDays * 24 + everyHours, 1))
            reminder.schedule = .every(hours: hours)
        case .weekdays:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: weekdayTime)
            let days = weekdays.isEmpty ? [2] : Array(weekdays).sorted()
            reminder.schedule = .weekdays(days: days, hour: comps.hour ?? 9, minute: comps.minute ?? 0)
            // Work out the next matching day from now.
            var probe = reminder
            probe.nextDue = Date()
            reminder.nextDue = probe.nextOccurrence(after: Date())
        }
        store.upsert(reminder)
        Task { await AlertScheduler.rescheduleAll() }
        dismiss()
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background(isOn ? Color.orange : Color.gray.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
