//
//  CapacityForecastCard.swift
//  PFSS
//
//  Reusable Operations workspace card for displaying
//  daily scheduling capacity and utilization.
//

import SwiftUI

struct CapacityForecastCard: View {

    let forecasts: [CapacityForecast]

    var title: String = "Capacity Forecast"
    var subtitle: String? = nil

    private var sortedForecasts: [CapacityForecast] {
        forecasts
    }

    private var averageUtilization: Double {
        guard !sortedForecasts.isEmpty else {
            return 0
        }

        let total = sortedForecasts.reduce(0.0) {
            $0 + normalizedUtilization($1.utilization)
        }

        return total / Double(sortedForecasts.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            header

            if sortedForecasts.isEmpty {
                emptyState
            } else {
                forecastRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardStyle()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle,
                   !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(averageUtilization, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(capacityColor(for: averageUtilization))

                Text("Average")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Forecast Rows

    private var forecastRows: some View {
        VStack(spacing: 14) {
            ForEach(sortedForecasts) { forecast in
                forecastRow(forecast)
            }
        }
    }

    private func forecastRow(
        _ forecast: CapacityForecast
    ) -> some View {
        let utilization = normalizedUtilization(forecast.utilization)

        return VStack(alignment: .leading, spacing: 7) {

            HStack(spacing: 10) {
                Text(forecast.day)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text(utilization, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(capacityColor(for: utilization))
            }

            ProgressView(value: utilization)
                .tint(capacityColor(for: utilization))

            Text(capacityDescription(for: utilization))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(forecast.day), \(utilization.formatted(.percent.precision(.fractionLength(0)))) capacity, \(capacityDescription(for: utilization))"
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No capacity forecast available")
                .font(.subheadline.weight(.medium))

            Text("Capacity data will appear after schedules and technician availability are loaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func normalizedUtilization(
        _ utilization: Double
    ) -> Double {
        min(max(utilization, 0), 1)
    }

    private func capacityColor(
        for utilization: Double
    ) -> Color {
        switch normalizedUtilization(utilization) {
        case 0..<0.60:
            return .green

        case 0.60..<0.85:
            return .blue

        case 0.85..<1.0:
            return .orange

        default:
            return .red
        }
    }

    private func capacityDescription(
        for utilization: Double
    ) -> String {
        switch normalizedUtilization(utilization) {
        case 0..<0.60:
            return "Open capacity"

        case 0.60..<0.85:
            return "Healthy workload"

        case 0.85..<1.0:
            return "Nearly full"

        default:
            return "At capacity"
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            CapacityForecastCard(
                forecasts: [
                    CapacityForecast(
                        day: "Today",
                        utilization: 0.94
                    ),
                    CapacityForecast(
                        day: "Tomorrow",
                        utilization: 0.81
                    ),
                    CapacityForecast(
                        day: "Friday",
                        utilization: 0.63
                    ),
                    CapacityForecast(
                        day: "Saturday",
                        utilization: 0.42
                    )
                ],
                subtitle: "Scheduled technician workload"
            )

            CapacityForecastCard(
                forecasts: []
            )
        }
        .padding()
    }
}
