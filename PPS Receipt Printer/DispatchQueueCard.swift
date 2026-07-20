//
//  DispatchQueueCard.swift
//  PFSS
//
//  Reusable card for jobs awaiting dispatch.
//

import SwiftUI

struct DispatchQueueCard: View {

    let item: DispatchQueueItem

    var onAssign: (() -> Void)? = nil
    var onViewDetails: (() -> Void)? = nil

    private var priorityTitle: String {
        switch item.priority {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        case .emergency:
            return "Emergency"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .low:
            return .secondary
        case .normal:
            return .blue
        case .high:
            return .orange
        case .emergency:
            return .red
        }
    }

    private var formattedDuration: String {
        let totalMinutes = max(Int(item.estimatedDuration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }

        if hours > 0 {
            return hours == 1 ? "1 hr" : "\(hours) hrs"
        }

        return "\(minutes) min"
    }

    private var confidenceText: String {
        let normalized = min(max(item.confidence, 0), 1)
        return "\(Int((normalized * 100).rounded()))% confidence"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            jobDetails

            if item.recommendedTechnician != nil {
                Divider()
                recommendation
            }

            if onAssign != nil || onViewDetails != nil {
                actionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardStyle()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.customerName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(item.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(priorityTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(priorityColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(priorityColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var jobDetails: some View {
        HStack(spacing: 16) {
            detailItem(
                icon: "clock",
                title: "Estimated Time",
                value: formattedDuration
            )

            Spacer(minLength: 8)

            detailItem(
                icon: "person.crop.circle.badge.questionmark",
                title: "Assignment",
                value: item.recommendedTechnician == nil
                    ? "Unassigned"
                    : "Recommended"
            )
        }
    }

    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended Technician")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.recommendedTechnician ?? "")
                        .font(.subheadline.weight(.semibold))

                    Text(confidenceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ProgressView(value: min(max(item.confidence, 0), 1))
                    .frame(width: 72)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let onViewDetails {
                Button(action: onViewDetails) {
                    Label("Details", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let onAssign {
                Button(action: onAssign) {
                    Label("Assign", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.recommendedTechnician == nil)
            }
        }
    }

    private func detailItem(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            DispatchQueueCard(
                item: DispatchQueueItem(
                    customerName: "Carter Residence",
                    address: "4424 Maple Avenue, Oklahoma City, OK",
                    estimatedDuration: 90 * 60,
                    priority: .high,
                    recommendedTechnician: "John Smith",
                    confidence: 0.96
                ),
                onAssign: {},
                onViewDetails: {}
            )

            DispatchQueueCard(
                item: DispatchQueueItem(
                    customerName: "Oak Ridge Office",
                    address: "5521 Oak Drive, Edmond, OK",
                    estimatedDuration: 45 * 60,
                    priority: .normal,
                    recommendedTechnician: nil,
                    confidence: 0
                ),
                onAssign: {},
                onViewDetails: {}
            )
        }
        .padding()
    }
}
