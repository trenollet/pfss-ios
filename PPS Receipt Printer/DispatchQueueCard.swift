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
    let rank: Int?
    let eligibility: OperationalRecommendationEligibility
    let evidence: [OperationalRecommendationEvidence]
    let distanceMiles: Double?
    let travelMinutes: Int?

    init(
        id: UUID,
        name: String,
        confidence: Double,
        proposedStart: Date,
        isRecommended: Bool,
        hasConflictFreeOpening: Bool,
        rank: Int? = nil,
        eligibility: OperationalRecommendationEligibility = .eligible,
        evidence: [OperationalRecommendationEvidence] = [],
        distanceMiles: Double? = nil,
        travelMinutes: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.confidence = min(max(confidence, 0), 1)
        self.proposedStart = proposedStart
        self.isRecommended = isRecommended
        self.hasConflictFreeOpening = hasConflictFreeOpening
        self.rank = rank
        self.eligibility = eligibility
        self.evidence = evidence
        self.distanceMiles = distanceMiles
        self.travelMinutes = travelMinutes
    }
}

struct DispatchQueueCard: View {
    let item: DispatchQueueItem
    let technicianOptions: [DispatchTechnicianOption]

    var onAssign: ((UUID, String) -> Void)? = nil
    var onViewDetails: (() -> Void)? = nil

    @State private var selectedTechnicianID: UUID?
    @State private var overrideReason = ""

    init(
        item: DispatchQueueItem,
        technicianOptions: [DispatchTechnicianOption] = [],
        onAssign: ((UUID, String) -> Void)? = nil,
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
        .onChange(of: selectedTechnicianID) {
            overrideReason = ""
        }
    }

    private var recommendedOption: DispatchTechnicianOption? {
        technicianOptions.first(where: \.isRecommended)
    }

    private var tiedLeaders: [DispatchTechnicianOption] {
        technicianOptions.filter { $0.rank == 1 && $0.eligibility != .ineligible }
    }

    private var hasTopTie: Bool {
        recommendedOption == nil && tiedLeaders.count > 1
    }

    private var selectedOption: DispatchTechnicianOption? {
        guard let selectedTechnicianID else { return nil }
        return technicianOptions.first { $0.id == selectedTechnicianID }
    }

    private var isOverrideSelection: Bool {
        guard let selectedTechnicianID else {
            return false
        }
        if hasTopTie,
           tiedLeaders.contains(where: { $0.id == selectedTechnicianID }) {
            return false
        }
        guard let recommendedID = recommendedOption?.id else {
            return true
        }
        return selectedTechnicianID != recommendedID
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.customerName)
                    .font(.headline)
                    .foregroundStyle(
                        item.priority == .emergency ? Color.red : Color.primary
                    )

                Text(item.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Label(
                priorityTitle,
                systemImage: item.priority == .emergency
                    ? "flag.fill"
                    : "flag"
            )
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
            if hasTopTie {
                Label(
                    "Top candidates tied: \(tiedLeaders.map(\.name).joined(separator: ", "))",
                    systemImage: "equal.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            } else if let recommendedOption {
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

                        if let reason = recommendedOption.evidence.first(where: {
                            $0.impact == .supporting
                        }) {
                            Text(reason.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggested Start")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(selectedOption.proposedStart.formatted(date: .abbreviated, time: .shortened))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 6) {
                        Image(systemName: selectionSymbol(selectedOption))
                        Text(selectionDetail(selectedOption))
                    }
                    .foregroundStyle(selectionColor(selectedOption))

                    if let miles = selectedOption.distanceMiles,
                       let minutes = selectedOption.travelMinutes {
                        Label(
                            String(format: "%.1f miles · %d min by Apple Maps", miles, minutes),
                            systemImage: "car.fill"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if let evidence = selectedOption.evidence.first(where: {
                        $0.impact == .blocking || $0.impact == .warning
                    }) {
                        Text(evidence.detail)
                            .font(.caption)
                            .foregroundStyle(
                                evidence.impact == .blocking
                                    ? Color.red
                                    : Color.orange
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isOverrideSelection {
                        TextField(
                            "Reason for choosing another technician",
                            text: $overrideReason,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    }

                    DisclosureGroup("Full score breakdown") {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(selectedOption.evidence) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: evidenceSymbol(item.impact))
                                        .foregroundStyle(evidenceColor(item.impact))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(item.category.rawValue)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(scoreText(item.scoreContribution))
                                                .monospacedDigit()
                                        }
                                        Text(item.title)
                                        Text(item.detail)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .font(.caption)
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
                    onAssign(selectedTechnicianID, overrideReason)
                } label: {
                    Label("Assign", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    selectedTechnicianID == nil ||
                    (isOverrideSelection && normalizedOverrideReason.isEmpty)
                )
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
        let rankText = option.rank.map { "Rank #\($0) · " } ?? ""
        let confidence = confidenceText(option.confidence)

        if option.hasConflictFreeOpening && option.eligibility != .ineligible {
            return "\(rankText)\(confidence) · Conflict-free opening"
        }
        return "\(rankText)\(confidence) · Manual override; review warnings."
    }

    private var normalizedOverrideReason: String {
        overrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scoreText(_ value: Double) -> String {
        value > 0 ? String(format: "+%.1f", value) : "—"
    }

    private func evidenceSymbol(
        _ impact: OperationalRecommendationEvidenceImpact
    ) -> String {
        switch impact {
        case .blocking: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .supporting: return "checkmark.circle.fill"
        case .informational: return "info.circle.fill"
        }
    }

    private func evidenceColor(
        _ impact: OperationalRecommendationEvidenceImpact
    ) -> Color {
        switch impact {
        case .blocking: return .red
        case .warning: return .orange
        case .supporting: return .green
        case .informational: return .secondary
        }
    }

    private func selectionSymbol(_ option: DispatchTechnicianOption) -> String {
        switch option.eligibility {
        case .eligible:
            return "checkmark.circle.fill"
        case .eligibleWithWarnings:
            return "exclamationmark.triangle.fill"
        case .ineligible:
            return "xmark.octagon.fill"
        }
    }

    private func selectionColor(_ option: DispatchTechnicianOption) -> Color {
        switch option.eligibility {
        case .eligible:
            return .secondary
        case .eligibleWithWarnings:
            return .orange
        case .ineligible:
            return .red
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
        onAssign: { _, _ in }
    )
    .padding()
}
