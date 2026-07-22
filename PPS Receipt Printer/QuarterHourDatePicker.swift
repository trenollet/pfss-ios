import Foundation
import SwiftUI

/// A date-and-time editor that limits scheduled times to quarter-hour increments.
struct QuarterHourDatePicker: View {
    @Binding var selection: Date

    var dateLabel = "Scheduled Date"
    var timeLabel = "Scheduled Time"

    private let calendar = Calendar.current
    private let minuteChoices = [0, 15, 30, 45]

    var body: some View {
        Group {
            DatePicker(
                dateLabel,
                selection: dateBinding,
                displayedComponents: .date
            )

            LabeledContent(timeLabel) {
                HStack(spacing: 8) {
                    Picker("Hour", selection: hourBinding) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()

                    Picker("Minute", selection: minuteBinding) {
                        ForEach(minuteChoices, id: \.self) { minute in
                            Text(String(format: ":%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { selection },
            set: { newDate in
                let time = calendar.dateComponents([.hour, .minute], from: selection)
                selection = calendar.date(
                    bySettingHour: time.hour ?? 0,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: newDate
                ) ?? newDate
            }
        )
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.hour, from: selection) },
            set: { newHour in updateTime(hour: newHour, minute: selectedMinute) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { selectedMinute },
            set: { newMinute in updateTime(hour: selectedHour, minute: newMinute) }
        )
    }

    private var selectedHour: Int {
        calendar.component(.hour, from: selection)
    }

    private var selectedMinute: Int {
        let minute = calendar.component(.minute, from: selection)
        return minuteChoices.min(by: { abs($0 - minute) < abs($1 - minute) }) ?? 0
    }

    private func updateTime(hour: Int, minute: Int) {
        selection = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: selection
        ) ?? selection
    }

    static func normalized(_ date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let quarterHours = [0, 15, 30, 45]
        let nearestMinute = quarterHours.min {
            abs($0 - minute) < abs($1 - minute)
        } ?? 0

        return calendar.date(
            bySettingHour: calendar.component(.hour, from: date),
            minute: nearestMinute,
            second: 0,
            of: date
        ) ?? date
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
