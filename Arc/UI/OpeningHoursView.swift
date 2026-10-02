import SwiftUI

struct OpeningHoursView: View {
    let schedule: OpeningSchedule?
    @State private var expanded = false
    var body: some View {
        if let schedule {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let today = schedule.weekday(at: timeline.date)
                VStack(alignment: .leading, spacing: 12) {
                    Label(schedule.status(at: timeline.date), systemImage: "clock")
                        .font(.headline)
                    Text("Today · \(schedule.hours(for: today))").font(.subheadline)
                    DisclosureGroup("Weekly opening hours", isExpanded: $expanded) {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                GridRow {
                                    Text(schedule.calendar.weekdaySymbols[day - 1])
                                    Text(schedule.hours(for: day)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .font(.subheadline.weight(day == today ? .semibold : .regular))
                                .foregroundStyle(day == today ? Color.primary : Color.secondary)
                            }
                        }.padding(.top, 12)
                    }.font(.subheadline)
                    if let note = schedule.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        } else {
            Label("Opening hours unavailable", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
