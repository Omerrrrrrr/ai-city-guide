import SwiftUI

/// Behind the Home screen's holiday banner tap — the banner itself only
/// has room for the name and a day count; this shows what the AI-written
/// `summary`/`activities` (grounded in the real holiday, see
/// `/holidays/upcoming`) actually describe. Both are optional: a holiday
/// whose enrichment failed or wasn't generated (no AI provider configured
/// server-side) still shows the real date/name, just without this detail.
struct HolidayDetailSheet: View {
    let holiday: UpcomingHoliday

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(holiday.name).font(.title3.bold())
                        if holiday.localName != holiday.name {
                            Text(holiday.localName).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let date = holiday.dateValue {
                            Text(date.formatted(date: .long, time: .omitted))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let summary = holiday.summary {
                        Text(summary).font(.body)
                    }

                    if let activities = holiday.activities, !activities.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "home.holiday.activities"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(activities, id: \.self) { activity in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Theme.gold).frame(width: 5, height: 5).padding(.top, 6)
                                    Text(activity).font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }
}
