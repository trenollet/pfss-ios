//
//  DashboardStatCard.swift
//  PFSS
//
//  Created by ChatGPT
//

import SwiftUI

struct DashboardStatCard: View {

    enum Trend {
        case up
        case down
        case neutral
    }

    let title: String
    let value: String
    let icon: String

    var subtitle: String? = nil
    var accentColor: Color = .blue
    var trend: Trend = .neutral
    var navigationIndicator = false

    private var trendIcon: String {
        switch trend {
        case .up:
            return "arrow.up.right"
        case .down:
            return "arrow.down.right"
        case .neutral:
            return "minus"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .up:
            return .green
        case .down:
            return .red
        case .neutral:
            return .secondary
        }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            HStack {

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accentColor)

                Spacer()

                Image(
                    systemName: navigationIndicator
                        ? "chevron.right.circle.fill"
                        : trendIcon
                )
                .foregroundStyle(
                    navigationIndicator
                        ? accentColor
                        : trendColor
                )
                .font(.caption)
            }

            Text(value)
                .font(.system(size: 30, weight: .bold))
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.headline)

            if let subtitle {

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 135)
        .dashboardCardStyle()
    }
}

#Preview {

    ScrollView {

        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 16
        ) {

            DashboardStatCard(
                title: "Jobs Awaiting Dispatch",
                value: "14",
                icon: "clipboard",
                subtitle: "3 High Priority",
                accentColor: .orange,
                trend: .up
            )

            DashboardStatCard(
                title: "Technicians Available",
                value: "7",
                icon: "person.2.fill",
                subtitle: "2 In Transit",
                accentColor: .green,
                trend: .neutral
            )

            DashboardStatCard(
                title: "Today's Schedule",
                value: "31",
                icon: "calendar",
                subtitle: "5 Remaining",
                accentColor: .blue,
                trend: .down
            )

            DashboardStatCard(
                title: "Capacity",
                value: "86%",
                icon: "gauge.high",
                subtitle: "Healthy",
                accentColor: .purple,
                trend: .up
            )
        }
        .padding()
    }
}
