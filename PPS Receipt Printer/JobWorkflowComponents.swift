//
//  JobWorkflowComponents.swift
//  PPS Receipt Printer
//
//  Brick 7: Reusable workflow presentation
//

import SwiftUI

extension JobWorkflowAccent {
    var color: Color {
        switch self {
        case .secondary: return .secondary
        case .blue: return .blue
        case .orange: return .orange
        case .purple: return .purple
        case .green: return .green
        case .red: return .red
        }
    }
}

struct JobWorkflowStatusCard: View {
    let context: JobWorkflowContext
    let action: () -> Void
    var performAction: ((JobWorkflowAction) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIELD WORKFLOW")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Label(
                        context.presentation.statusTitle,
                        systemImage: context.presentation.statusSystemImage
                    )
                    .font(.headline)
                }

                Spacer()

                Text("\(context.progressPercentage)%")
                    .font(.title3)
                    .fontWeight(.bold)
            }

            GeometryReader { geometry in
                let availableWidth = max(
                    geometry.size.width,
                    0
                )

                let progressWidth = availableWidth
                    * safeProgressFraction

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            Color.secondary.opacity(0.2)
                        )

                    Capsule()
                        .fill(context.presentation.accent.color)
                        .frame(
                            width: max(progressWidth, 0)
                        )
                }
            }
            .frame(height: 8)

            Button(action: action) {
                Label(
                    context.nextAction.title,
                    systemImage:
                        context.nextAction.systemImage
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(context.nextAction.presentation.accent.color)

            if let secondaryAction,
               let performAction {
                Button {
                    performAction(secondaryAction)
                } label: {
                    Label(
                        secondaryAction.title,
                        systemImage: secondaryAction.systemImage
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(secondaryAction.presentation.accent.color)
            }
        }
        .padding(.vertical, 4)
    }

    private var safeProgressFraction: CGFloat {
        let rawFraction =
            CGFloat(context.progressPercentage) / 100

        guard rawFraction.isFinite else {
            return 0
        }

        return min(
            max(rawFraction, 0),
            1
        )
    }

    private var secondaryAction: JobWorkflowAction? {
        context.availableActions.first {
            $0 != context.nextAction && $0 != .viewDetails
        }
    }
}

struct JobTimelineView: View {
    let events: [JobTimelineEvent]
    let employeeName: (UUID?) -> String?

    var body: some View {
        if events.isEmpty {
            ContentUnavailableView(
                "No Timeline Activity",
                systemImage: "clock.arrow.circlepath",
                description: Text(
                    "Workflow activity will appear here automatically."
                )
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(events.enumerated()),
                    id: \.element.id
                ) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 12, height: 12)

                            if index < events.count - 1 {
                                Rectangle()
                                    .fill(.secondary.opacity(0.3))
                                    .frame(width: 2, height: 42)
                            }
                        }
                        .padding(.top, 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .fontWeight(.semibold)

                            HStack(spacing: 6) {
                                Text(
                                    event.timestamp.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )

                                if let name = employeeName(
                                    event.employeeID
                                ) {
                                    Text("• \(name)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let note = event.note,
                               !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
    }
}
