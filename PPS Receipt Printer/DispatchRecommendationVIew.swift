//
//  DispatchRecommendationView.swift
//  PPS Receipt Printer
//
//  Brick 12 — Sprint 2
//  Reusable explainable dispatch recommendation interface.
//

import SwiftUI

struct DispatchRecommendationView: View {
    let job: JobRecord
    let employees: [EmployeeRecord]
    let jobs: [JobRecord]

    @Binding var selectedPolicy: DecisionPolicy

    var maximumAlternatives: Int = 3
    var onSelect: ((DispatchDecision) -> Void)? = nil

    private var result: DispatchDecisionResult {
        DispatchDecisionEngine.evaluate(
            job: job,
            employees: employees,
            jobs: jobs,
            policy: selectedPolicy
        )
    }

    private var bestDecision: DispatchDecision? {
        result.bestDecision
    }

    private var alternativeDecisions: [DispatchDecision] {
        Array(
            result.decisions
                .dropFirst()
                .prefix(max(maximumAlternatives, 0))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            policyPicker

            if let bestDecision {
                bestRecommendationCard(bestDecision)

                if !alternativeDecisions.isEmpty {
                    alternativesSection
                }
            } else {
                noRecommendationCard
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Policy

    private var policyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dispatch Policy")
                .font(.subheadline.weight(.semibold))

            Picker("Dispatch Policy", selection: $selectedPolicy) {
                ForEach(DecisionPolicy.allCases) { policy in
                    Text(policy.displayName)
                        .tag(policy)
                }
            }
            .pickerStyle(.menu)

            Text(selectedPolicy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Best Recommendation

    private func bestRecommendationCard(
        _ decision: DispatchDecision
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended Technician")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(decision.employee.displayName)
                        .font(.title3.weight(.semibold))

                    Text(openingDescription(for: decision))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                confidenceBadge(for: decision)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Why this technician")
                    .font(.subheadline.weight(.semibold))

                ForEach(decision.reasons) { reason in
                    reasonRow(reason)
                }
            }

            if let onSelect {
                Button {
                    onSelect(decision)
                } label: {
                    Label(
                        "Assign \(decision.employee.displayName)",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.background)
                .shadow(radius: 1, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func confidenceBadge(
        for decision: DispatchDecision
    ) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(decision.confidencePercentage)%")
                .font(.title3.monospacedDigit().weight(.bold))

            Text("\(decision.confidence.displayName) Confidence")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Image(
                        systemName: index < decision.confidence.starCount
                            ? "star.fill"
                            : "star"
                    )
                    .font(.caption2)
                }
            }
            .accessibilityLabel(
                "\(decision.confidence.starCount) out of 5 stars"
            )
        }
    }

    private func reasonRow(
        _ reason: DecisionReason
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(
                systemName: reason.isPositive
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(
                reason.isPositive
                    ? .green
                    : .orange
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(reason.title)
                    .font(.subheadline.weight(.medium))

                Text(reason.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if reason.weight > 0 {
                Text("+\(Int(reason.weight.rounded()))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Weight \(Int(reason.weight.rounded()))"
                    )
            }
        }
    }

    // MARK: - Alternatives

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alternatives")
                .font(.headline)

            ForEach(alternativeDecisions) { decision in
                Button {
                    onSelect?(decision)
                } label: {
                    alternativeRow(decision)
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil)
            }
        }
    }

    private func alternativeRow(
        _ decision: DispatchDecision
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(decision.employee.displayName)
                    .font(.subheadline.weight(.semibold))

                Text(openingDescription(for: decision))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(decision.confidencePercentage)%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))

                Text(decision.confidence.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if onSelect != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Empty State

    private var noRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "No Available Technician",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .font(.headline)

            Text(
                "PFSS could not find a conflict-free opening for this job using the selected dispatch policy."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !result.unavailableEmployees.isEmpty {
                Text(
                    "\(result.unavailableEmployees.count) technician\(result.unavailableEmployees.count == 1 ? " was" : "s were") evaluated."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    // MARK: - Formatting

    private func openingDescription(
        for decision: DispatchDecision
    ) -> String {
        let start = decision.opening.start
        let end = decision.opening.end

        return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}
