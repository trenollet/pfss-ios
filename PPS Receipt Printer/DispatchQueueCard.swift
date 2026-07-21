//
//  DispatchQueueCard.swift
//  PFSS
//
//  Reusable card for jobs awaiting dispatch. Recommendations are advisory:
//  the recommended technician is selected by default, while dispatchers may
//  choose any active technician.
//

import SwiftUI

struct DispatchTechnicianOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let confidence: Double
    let proposedStart: Date
    let isRecommended: Bool
    let hasConflictFreeOpening: Bool
}

struct DispatchQueueCard: View {
    let item: DispatchQueueItem
    let technicianOptions: [DispatchTechnicianOption]

    var onAssign: ((UUID) -> Void)? = nil
    var onViewDetails: (() -> Void)? = nil

    @State private var selectedTechnicianID: UUID?

    init(
        item: DispatchQueueItem,
        technicianOptions: [DispatchTechnicianOption] = [],
        onAssign: ((UUID) -> Void)? = nil,
        onViewDetails: (() -> Void)? = nil
    ) {
        self.item = item
        self.technicianOptions = technicianOptions
        self.onAssign = onAssign
        self.onViewDetails = onViewDetails

        _selectedTechnicianID = State(
            initialValue: technicianOptions.first(where: \.isRecommended)?.id
                ?? technicianOptions.first?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            jobDetails
            Divider()
            technicianSelection

            if onAssign != nil || onViewDetails != nil {
                actionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardStyle()
        .onChange(of: technicianOptions.map(\.id)) {
            if let selectedTechnicianID,
               technicianOptions.contains(where: { $0.id == selectedTechnicianID }) {
                return
            }
            self.selectedTechnicianID = recommendedOption?.id
                ?? technicianOptions.first?.id
        }
    }

    private var recommendedOption: DispatchTechnicianOption? {
        technicianOptions.first(where: \.isRecommended)
    }

    private var selectedOption: DispatchTechnicianOption? {
        guard let selectedTechnicianID else { return nil }
        return technicianOptions.first { $0.id == selectedTechnicianID }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.customerName)
                    .font(.headline)

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
                value: selectedOption?.name ?? "Unassigned"
            )
        }
    }

    private var technicianSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let recommendedOption {
                HStack(spacing: 10) {
                    Image(systemName: "star.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended: \(recommendedOption.name)")
                            .font(.subheadline.weight(.semibold))

                        Text("\(confidenceText(recommendedOption.confidence)) confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("No conflict-free recommendation", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            Picker("Assign Technician", selection: $selectedTechnicianID) {
                Text("Select a technician").tag(UUID?.none)

                ForEach(technicianOptions) { option in
                    Text(optionLabel(option)).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedOption {
                HStack(spacing: 6) {
                    Image(
                        systemName: selectedOption.hasConflictFreeOpening
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    Text(selectionDetail(selectedOption))
                }
                .font(.caption)
                .foregroundStyle(
                    selectedOption.hasConflictFreeOpening
                        ? Color.secondary
                        : Color.orange
                )
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
                Button {
                    guard let selectedTechnicianID else { return }
                    onAssign(selectedTechnicianID)
                } label: {
                    Label("Assign", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTechnicianID == nil)
            }
        }
    }

    private var priorityTitle: String {
        switch item.priority {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .emergency: return "Emergency"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .low: return .secondary
        case .normal: return .blue
        case .high: return .orange
        case .emergency: return .red
        }
    }

    private var formattedDuration: String {
        let totalMinutes = max(Int(item.estimatedDuration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 { return "\(hours) hr \(minutes) min" }
        if hours > 0 { return hours == 1 ? "1 hr" : "\(hours) hrs" }
        return "\(minutes) min"
    }

    private func confidenceText(_ confidence: Double) -> String {
        let normalized = min(max(confidence, 0), 1)
        return "\(Int((normalized * 100).rounded()))%"
    }

    private func optionLabel(_ option: DispatchTechnicianOption) -> String {
        option.name
    }

    private func selectionDetail(_ option: DispatchTechnicianOption) -> String {
        if option.hasConflictFreeOpening {
            return "Proposed start: \(option.proposedStart.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Manual override selected; review this technician's schedule."
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
            }
        }
    }
}

#Preview {
    DispatchQueueCard(
        item: DispatchQueueItem(
            customerName: "Carter Residence",
            address: "4424 Maple Avenue, Oklahoma City, OK",
            estimatedDuration: 90 * 60,
            priority: .high,
            recommendedTechnician: "John Smith",
            confidence: 0.96
        ),
        technicianOptions: [
            DispatchTechnicianOption(
                id: UUID(),
                name: "John Smith",
                confidence: 0.96,
                proposedStart: Date(),
                isRecommended: true,
                hasConflictFreeOpening: true
            ),
            DispatchTechnicianOption(
                id: UUID(),
                name: "Sarah Jones",
                confidence: 0.82,
                proposedStart: Date(),
                isRecommended: false,
                hasConflictFreeOpening: true
            )
        ],
        onAssign: { _ in }
    )
    .padding()
}
