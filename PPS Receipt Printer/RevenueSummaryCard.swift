//
//  RevenueSummaryCard.swift
//  PFSS
//
//  Reusable Operations workspace card for displaying
//  scheduled, completed, invoiced, and collected revenue.
//

import SwiftUI

struct RevenueSummaryCard: View {

    let summary: RevenueSummary

    var title: String = "Revenue Summary"
    var subtitle: String? = nil

    private var totalPipeline: Double {
        max(summary.scheduled, 0)
    }

    private var collectionProgress: Double {
        guard summary.invoiced > 0 else {
            return 0
        }

        return min(
            max(summary.collected / summary.invoiced, 0),
            1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            header

            primaryRevenue

            Divider()

            revenueGrid

            collectionSection
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

            Image(systemName: "dollarsign.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Primary Revenue

    private var primaryRevenue: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scheduled Revenue")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(currency(totalPipeline))
                .font(.system(size: 30, weight: .bold))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Revenue Grid

    private var revenueGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            spacing: 16
        ) {
            metric(
                title: "Completed",
                value: summary.completed,
                icon: "checkmark.circle.fill",
                color: .blue
            )

            metric(
                title: "Invoiced",
                value: summary.invoiced,
                icon: "doc.text.fill",
                color: .orange
            )

            metric(
                title: "Collected",
                value: summary.collected,
                icon: "banknote.fill",
                color: .green
            )

            metric(
                title: "Outstanding",
                value: max(summary.invoiced - summary.collected, 0),
                icon: "clock.fill",
                color: .red
            )
        }
    }

    private func metric(
        title: String,
        value: Double,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(currency(max(value, 0)))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Collection Progress

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 7) {

            HStack {
                Text("Invoice Collection")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(
                    collectionProgress,
                    format: .percent.precision(.fractionLength(0))
                )
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(collectionColor)
            }

            ProgressView(value: collectionProgress)
                .tint(collectionColor)

            Text(collectionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Invoice collection \(collectionProgress.formatted(.percent.precision(.fractionLength(0)))), \(collectionDescription)"
        )
    }

    // MARK: - Helpers

    private var collectionColor: Color {
        switch collectionProgress {
        case 0..<0.50:
            return .red

        case 0.50..<0.80:
            return .orange

        default:
            return .green
        }
    }

    private var collectionDescription: String {
        switch collectionProgress {
        case 0 where summary.invoiced <= 0:
            return "No invoices issued"

        case 0..<0.50:
            return "Collection follow-up recommended"

        case 0.50..<0.80:
            return "Collections are progressing"

        default:
            return "Strong collection performance"
        }
    }

    private func currency(
        _ amount: Double
    ) -> String {
        amount.formatted(
            .currency(code: Locale.current.currency?.identifier ?? "USD")
                .precision(.fractionLength(0))
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            RevenueSummaryCard(
                summary: RevenueSummary(
                    scheduled: 3420,
                    completed: 2180,
                    invoiced: 2450,
                    collected: 1960
                ),
                subtitle: "Today"
            )

            RevenueSummaryCard(
                summary: RevenueSummary(
                    scheduled: 0,
                    completed: 0,
                    invoiced: 0,
                    collected: 0
                )
            )
        }
        .padding()
    }
}
