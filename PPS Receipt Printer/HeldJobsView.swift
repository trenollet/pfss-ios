//
//  HeldJobsView.swift
//  PPS Receipt Printer
//
//  Phase 19 – Shared discovery surface for recurring work placed on hold.
//

import SwiftUI

struct HeldJobsView: View {
    @EnvironmentObject private var store: AppDataStore

    private var heldTemplates: [RecurringWorkTemplate] {
        store.recurringWorkTemplates
            .filter { $0.status == .held }
            .sorted {
                ($0.holdStartedAt ?? $0.updatedAt) >
                    ($1.holdStartedAt ?? $1.updatedAt)
            }
    }

    var body: some View {
        List {
            if heldTemplates.isEmpty {
                ContentUnavailableView(
                    "No Jobs on Hold",
                    systemImage: "pause.rectangle",
                    description: Text(
                        "Recurring jobs placed on hold will appear here until the series is released."
                    )
                )
            } else {
                Section("Held Recurring Jobs") {
                    ForEach(heldTemplates) { template in
                        NavigationLink {
                            RecurringWorkManagementView(
                                templateID: template.id
                            )
                        } label: {
                            heldTemplateRow(template)
                        }
                    }
                }
            }
        }
        .navigationTitle("Jobs on Hold")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heldTemplateRow(
        _ template: RecurringWorkTemplate
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(customerName(for: template.prototype.customerNumber))
                .font(.headline)

            Label(
                siteName(for: template.prototype.siteID),
                systemImage: "mappin.circle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Label(ruleName(template.rule), systemImage: "repeat")
                Spacer()
                Label("On Hold", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline.weight(.semibold))

            if let heldDate = template.heldScheduledDate {
                Text(
                    "Held occurrence: \(heldDate.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let holdStartedAt = template.holdStartedAt {
                Text(
                    "Placed on hold: \(holdStartedAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func customerName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return customerNumber
        }
        if !customer.businessName.isEmpty { return customer.businessName }
        if !customer.contactName.isEmpty { return customer.contactName }
        return customerNumber
    }

    private func siteName(for siteID: UUID?) -> String {
        guard let siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "Site not selected"
        }
        if !site.siteName.isEmpty { return site.siteName }
        if !site.serviceAddress.isEmpty { return site.serviceAddress }
        return "Site"
    }

    private func ruleName(_ rule: RecurringWorkRule) -> String {
        let unitName: String
        switch rule.unit {
        case .day: unitName = rule.interval == 1 ? "day" : "days"
        case .week: unitName = rule.interval == 1 ? "week" : "weeks"
        case .month: unitName = rule.interval == 1 ? "month" : "months"
        case .year: unitName = rule.interval == 1 ? "year" : "years"
        }
        return rule.interval == 1
            ? "Every \(unitName)"
            : "Every \(rule.interval) \(unitName)"
    }
}
