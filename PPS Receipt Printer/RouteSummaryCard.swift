//
//  RouteSummaryCard.swift
//  PPS Receipt Printer
//
//  Brick 6D.1: Configurable route-planning summary
//

import SwiftUI

struct RouteSummaryCard: View {
    let summary: DailyRouteOptimizer.RouteSummary
    let isOptimized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(
                    "Today's Route",
                    systemImage: "map.fill"
                )
                .font(.headline)
                .fontWeight(.bold)

                Spacer()

                if isOptimized {
                    Label(
                        "Optimized",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                routeMetric(
                    title: "Stops",
                    value: "\(summary.stopCount)",
                    systemImage: "mappin.and.ellipse"
                )

                Spacer()

                routeMetric(
                    title: "Distance",
                    value: distanceText,
                    systemImage: "road.lanes"
                )

                Spacer()

                routeMetric(
                    title: "Drive Time",
                    value: durationText(
                        minutes:
                            summary.estimatedDriveMinutes
                    ),
                    systemImage: "car.fill"
                )
            }

            Divider()

            VStack(spacing: 10) {
                summaryRow(
                    title: "Estimated Drive Time",
                    value: durationText(
                        minutes:
                            summary.estimatedDriveMinutes
                    )
                )

                summaryRow(
                    title: "Planning Buffer",
                    value: durationText(
                        minutes:
                            summary.planningBufferMinutes
                    )
                )

                summaryRow(
                    title: "Total Planned Route",
                    value: durationText(
                        minutes:
                            summary.plannedRouteMinutes
                    ),
                    isEmphasized: true
                )
            }

            Text(routeEstimateExplanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
        .accessibilityElement(children: .combine)
    }

    private var distanceText: String {
        let miles = summary.totalDistanceMiles

        if miles < 0.1 {
            return "< 0.1 mi"
        }

        return miles.formatted(
            .number.precision(.fractionLength(1))
        ) + " mi"
    }

    private var routeEstimateExplanation: String {
        if summary.includeBuffersInPlannedTime {
            return "Total planned route includes the business's daily and per-stop buffers. Distance and drive time use straight-line estimates."
        }

        return "Planning buffers are shown for reference but are not included in total planned route time. Distance and drive time use straight-line estimates."
    }

    private func durationText(
        minutes: Int
    ) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return hours == 1
                ? "1 hr"
                : "\(hours) hr"
        }

        return "\(hours) hr \(remainingMinutes) min"
    }

    private func summaryRow(
        title: String,
        value: String,
        isEmphasized: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(
                    isEmphasized
                        ? .primary
                        : .secondary
                )

            Spacer()

            Text(value)
                .fontWeight(
                    isEmphasized
                        ? .bold
                        : .semibold
                )
        }
        .font(
            isEmphasized
                ? .subheadline
                : .caption
        )
    }

    private func routeMetric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                title,
                systemImage: systemImage
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct RouteStopBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(.blue)
            .clipShape(Circle())
            .accessibilityLabel("Stop \(number)")
    }
}
