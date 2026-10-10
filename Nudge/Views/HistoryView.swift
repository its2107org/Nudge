import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: ReminderStore

    private var shareText: String {
        var lines = ["Nudge history"]
        for entry in store.log {
            var line = "\(entry.doneDate.formatted(date: .abbreviated, time: .shortened)): \(entry.title)"
            if let dose = entry.doseNote { line += ", \(dose)" }
            if let site = entry.site { line += ", \(site)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                if store.log.isEmpty {
                    Text("Nothing yet. Each time you tap Done, it's recorded here with the date and time.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.log) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.title).font(.headline)
                            Spacer()
                            Text(entry.doneDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if let dose = entry.doseNote { Label(dose, systemImage: "cross.vial") }
                            if let site = entry.site { Label(site, systemImage: "figure.stand") }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        if entry.doneDate.timeIntervalSince(entry.dueDate) > 3600 {
                            Text("Done \(ReminderSchedule.describe(hours: entry.doneDate.timeIntervalSince(entry.dueDate) / 3600)) late")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.deleteLog(entry.id) }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.log.isEmpty {
                    ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share history")
                }
            }
        }
    }
}
