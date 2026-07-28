//
//  TechnicianStatusCard.swift
//  PFSS
//
//  Reusable technician status card for the Operations workspace.
//

import SwiftUI

struct TechnicianStatusCard: View {

    let model: TechnicianStatusModel
    var onViewSchedule: (() -> Void)? = nil

    private var utilizationValue: Double {
        min(max(model.utilization, 0), 1)
    }

    private var statusColor: Color {
        switch model.status {
        case .available:
            return .green
        case .working:
            return .blue
        case .traveling:
            return .orange
        case .travelPaused:
            return .yellow
        case .lunch:
            return .yellow
        case .offline:
            return .secondary
        case .overtime:
            return .red
        }
    }

    private var statusIcon: String {
        switch model.status {
        case .available:
            return "checkmark.circle.fill"
        case .working:
            return "hammer.fill"
        case .traveling:
            return "car.fill"
        case .travelPaused:
            return "pause.circle.fill"
        case .lunch:
            return "fork.knife"
        case .offline:
            return "moon.fill"
        case .overtime:
            return "exclamationmark.triangle.fill"
        }
    }

    private var nextOpeningText: String {
        guard let nextOpening = model.nextOpening else {
            return "No opening"
        }

        return nextOpening.formatted(
            date: .omitted,
            time: .shortened
        )
    }

    private var revenueText: String {
        model.revenueToday.formatted(
            .currency(code: Locale.current.currency?.identifier ?? "USD")
                .precision(.fractionLength(0))
        )
    }

    private var utilizationText: String {
        utilizationValue.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            utilizationSection
            metricsGrid

            if let confidence = model.confidence {
                confidenceRow(confidence)
            }

            if let onViewSchedule {
                Button(action: onViewSchedule) {
                    Label("View Schedule", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardStyle()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))

                Text(initials)
                    .font(.headline)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)

                Label(model.status.displayName, systemImage: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 8)

            if model.status == .overtime {
                Text("Attention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.red.opacity(0.12), in: Capsule())
            }
        }
    }

    private var utilizationSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Current Utilization")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(utilizationText)
                    .font(.subheadline.weight(.semibold))
            }

            ProgressView(value: utilizationValue)
                .tint(utilizationTint)
                .accessibilityLabel("Current utilization")
                .accessibilityValue(utilizationText)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            alignment: .leading,
            spacing: 14
        ) {
            metric(
                title: "Jobs Today",
                value: String(model.jobsToday),
                icon: "briefcase.fill"
            )

            metric(
                title: "Next Opening",
                value: nextOpeningText,
                icon: "clock.fill"
            )

            metric(
                title: "Travel Time",
                value: "\(max(model.travelMinutes, 0)) min",
                icon: "car.fill"
            )

            metric(
                title: "Revenue Today",
                value: revenueText,
                icon: "dollarsign.circle.fill"
            )
        }
    }

    private func metric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confidenceRow(_ rawConfidence: Double) -> some View {
        let normalizedConfidence = min(max(rawConfidence, 0), 1)
        let confidenceText = normalizedConfidence.formatted(
            .percent.precision(.fractionLength(0))
        )

        return HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)

            Text("Recommendation Confidence")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(confidenceText)
                .font(.caption.weight(.semibold))
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let components = model.name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)

        let value = components.compactMap(\.first)

        return value.isEmpty
            ? "?"
            : String(value).uppercased()
    }

    private var utilizationTint: Color {
        switch utilizationValue {
        case ..<0.75:
            return .green
        case ..<0.9:
            return .orange
        default:
            return .red
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TechnicianStatusCard(
                model: TechnicianStatusModel(
                    name: "John Smith",
                    status: .available,
                    jobsToday: 5,
                    utilization: 0.72,
                    nextOpening: Calendar.current.date(
                        byAdding: .hour,
                        value: 2,
                        to: Date()
                    ),
                    travelMinutes: 18,
                    revenueToday: 840,
                    confidence: 0.94
                ),
                onViewSchedule: {}
            )

            TechnicianStatusCard(
                model: TechnicianStatusModel(
                    name: "Michael Davis",
                    status: .overtime,
                    jobsToday: 8,
                    utilization: 1.08,
                    nextOpening: nil,
                    travelMinutes: 34,
                    revenueToday: 1_420,
                    confidence: nil
                )
            )
        }
        .padding()
    }
}
