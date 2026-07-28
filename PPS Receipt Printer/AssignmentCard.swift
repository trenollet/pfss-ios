//
//  AssignmentCard.swift
//  PPS Receipt Printer
//

import SwiftUI

struct AssignmentCard: View {
    let assignment: Assignment
    let employees: [EmployeeRecord]
    let customers: [Customer]
    let sites: [CustomerSite]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customerDisplayName)
                        .font(.headline.weight(.bold))

                    Label(siteDisplayName, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    AssignmentStatusBadge(status: assignment.status)

                    Text(assignment.scheduling.displayDateText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(assignment.scheduling.displayTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label(primaryTechnicianName, systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(
                        assignment.primaryTechnicianID == nil ? .secondary : .primary
                    )

                Spacer(minLength: 8)

                if assignment.supportingTechnicianIDs.isEmpty == false {
                    Label(
                        "+\(assignment.supportingTechnicianIDs.count)",
                        systemImage: "person.2.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryTechnicianName: String {
        guard let employeeID = assignment.primaryTechnicianID else {
            return "Primary technician not assigned"
        }

        return employees.first { $0.id == employeeID }?.displayName
            ?? "Unknown technician"
    }

    private var customerDisplayName: String {
        guard let customer = customers.first(where: {
            $0.customerNumber == assignment.customerNumber
        }) else {
            return assignment.customerNumber.isEmpty
                ? "Unknown Customer"
                : assignment.customerNumber
        }

        let businessName = customer.businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contactName = customer.contactName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !businessName.isEmpty { return businessName }
        if !contactName.isEmpty { return contactName }
        return customer.customerNumber
    }

    private var siteDisplayName: String {
        guard let siteID = assignment.siteID,
              let site = sites.first(where: { $0.id == siteID }) else {
            return "No site assigned"
        }

        let name = site.siteName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Site" : name
    }
}
//
//  AssignmentCard.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/21/26.
//

import Foundation
