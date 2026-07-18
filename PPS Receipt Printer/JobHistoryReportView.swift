//
//  JobHistoryReportView.swift
//  PPS Receipt Printer
//
//  Brick 9: Automatic Time Tracking
//

import SwiftUI

struct JobHistoryReportView: View {
    @EnvironmentObject var store: AppDataStore

    private var completedJobs: [JobRecord] {
        store.jobs
            .filter { $0.status == .completed }
            .sorted { reportDate(for: $0) > reportDate(for: $1) }
    }

    var body: some View {
        List {
            if completedJobs.isEmpty {
                ContentUnavailableView(
                    "No Job History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Completed jobs will appear here."
                    )
                )
            } else {
                ForEach(completedJobs) { job in
                    jobHistoryRow(job)
                }
            }
        }
        .navigationTitle("Job History Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func jobHistoryRow(
        _ job: JobRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.jobNumber)
                    .font(.headline)

                Spacer()

                Text(invoiceStatus(for: job))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            Text(customerName(for: job.customerNumber))
                .font(.subheadline)

            LabeledContent("Date") {
                Text(
                    reportDate(for: job),
                    format: .dateTime
                        .month()
                        .day()
                        .year()
                )
            }

            LabeledContent("Technician(s)") {
                Text(technicianNames(for: job))
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Time on Job") {
                Text(formattedTimeOnJob(for: job))
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 5)
    }

    private func customerName(
        for customerNumber: String
    ) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return customerNumber
        }

        if !customer.businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            return customer.businessName
        }

        if !customer.contactName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            return customer.contactName
        }

        return customerNumber
    }

    private func technicianNames(
        for job: JobRecord
    ) -> String {
        let employeeIDs = [
            job.primaryTechnicianID,
            job.secondaryTechnicianID
        ].compactMap { $0 }

        let names = employeeIDs.compactMap { employeeID in
            store.employees.first(where: {
                $0.id == employeeID
            })?.displayName
        }

        return names.isEmpty
            ? "Unassigned"
            : names.joined(separator: ", ")
    }

    private func formattedTimeOnJob(
        for job: JobRecord
    ) -> String {
        guard let duration = job.timeOnJob else {
            return "—"
        }

        let totalMinutes = max(
            Int(duration / 60),
            0
        )
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        switch (hours, minutes) {
        case (0, let minutes):
            return "\(minutes) min"
        case (let hours, 0):
            return hours == 1
                ? "1 hr"
                : "\(hours) hrs"
        default:
            let hourText = hours == 1
                ? "1 hr"
                : "\(hours) hrs"
            return "\(hourText) \(minutes) min"
        }
    }

    private func invoiceStatus(
        for job: JobRecord
    ) -> String {
        guard let invoice = store.invoice(for: job) else {
            return "Not Invoiced"
        }

        return invoice.status.rawValue
    }

    private func reportDate(
        for job: JobRecord
    ) -> Date {
        job.completedDate ?? job.scheduledDate
    }
}
