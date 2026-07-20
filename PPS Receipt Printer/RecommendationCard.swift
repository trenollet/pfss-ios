//
//  RecommendationCard.swift
//  PFSS
//

import SwiftUI

struct RecommendationCard: View {

    let item: RecommendationItem
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {

            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {

                HStack {
                    Text(item.title)
                        .font(.headline)

                    Spacer()

                    Text(item.priority.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(iconColor.opacity(0.15))
                        .foregroundStyle(iconColor)
                        .clipShape(Capsule())
                }

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action {
                    Button("Apply Recommendation") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardStyle()
    }

    private var iconColor: Color {
        switch item.priority {
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private var iconName: String {
        switch item.priority {
        case .low:
            return "lightbulb"
        case .medium:
            return "exclamationmark.circle"
        case .high:
            return "bolt.fill"
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            RecommendationCard(
                item: RecommendationItem(
                    title: "Reassign Afternoon Job",
                    detail: "Move the 2:30 PM appointment to Mike Jones to reduce drive time by 22 minutes.",
                    priority: .high
                )
            )

            RecommendationCard(
                item: RecommendationItem(
                    title: "Open Capacity",
                    detail: "Sarah has room for one additional 90-minute service today.",
                    priority: .low
                ),
                action: {}
            )
        }
        .padding()
    }
}
