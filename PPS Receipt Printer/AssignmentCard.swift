//
//  AssignmentCard.swift
//  PPS Receipt Printer
//

import SwiftUI

struct AssignmentCard: View {
    let assignment: Assignment
    let employees: [EmployeeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment.jobNumber)
                        .font(.headline)

                    Text(assignment.assignmentNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                AssignmentStatusBadge(status: assignment.status)
            }

            Divider()

            Label(assignment.customerNumber, systemImage: "person.crop.circle")
                .font(.subheadline)

            Label(primaryTechnicianName, systemImage: "person.fill")
                .font(.subheadline)
                .foregroundStyle(
                    assignment.primaryTechnicianID == nil ? .secondary : .primary
                )

            HStack(spacing: 14) {
                Label(
                    assignment.scheduling.mode.rawValue,
                    systemImage: "calendar.badge.clock"
                )

                if assignment.supportingTechnicianIDs.isEmpty == false {
                    Label(
                        "+\(assignment.supportingTechnicianIDs.count)",
                        systemImage: "person.2.fill"
                    )
                }

                if let routeSequence = assignment.routeSequence {
                    Label("Stop \(routeSequence)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
}
//
//  AssignmentCard.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/21/26.
//

import Foundation
