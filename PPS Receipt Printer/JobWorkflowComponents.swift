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
    var onCorrect: ((JobTimelineEvent) -> Void)? = nil

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

                            if event.type == .timelineCorrected,
                               let original = event.originalTimestamp,
                               let corrected = event.correctedTimestamp {
                                Text(
                                    "\(original.formatted(date: .abbreviated, time: .shortened)) → \(corrected.formatted(date: .abbreviated, time: .shortened))"
                                )
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        if let onCorrect,
                           event.type != .note,
                           event.type != .timelineCorrected {
                            Button {
                                onCorrect(event)
                            } label: {
                                Image(systemName: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Correct \(event.title) time")
                        }
                    }
                }
            }
        }
    }
}

struct TimelineCorrectionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let event: JobTimelineEvent
    let actorName: String
    let onSave: (Date, String) -> Bool

    @State private var correctedTimestamp: Date
    @State private var reason = ""
    @State private var showingSaveError = false

    init(
        event: JobTimelineEvent,
        actorName: String,
        onSave: @escaping (Date, String) -> Bool
    ) {
        self.event = event
        self.actorName = actorName
        self.onSave = onSave
        _correctedTimestamp = State(initialValue: event.timestamp)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Timeline Event") {
                    LabeledContent("Event", value: event.title)
                    LabeledContent(
                        "Original Time",
                        value: event.timestamp.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }

                Section {
                    DatePicker(
                        "Corrected Date",
                        selection: $correctedTimestamp,
                        displayedComponents: [.date]
                    )

                    DatePicker(
                        "Corrected Time",
                        selection: $correctedTimestamp,
                        displayedComponents: [.hourAndMinute]
                    )

                    TextField(
                        "Reason for correction (required)",
                        text: $reason,
                        axis: .vertical
                    )
                        .lineLimit(2...5)
                } header: {
                    Text("Correction")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "Change the corrected date or time and enter a reason to enable Save."
                        )
                        Text(
                            "The original time will remain in the audit history. Correction recorded by \(actorName)."
                        )
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Correct Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Correction Not Saved", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(
                    "Confirm that the selected employee has the Owner or Manager role, then try again."
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(correctedTimestamp, trimmedReason) {
                            dismiss()
                        } else {
                            showingSaveError = true
                        }
                    }
                    .disabled(
                        trimmedReason.isEmpty ||
                        correctedTimestamp == event.timestamp
                    )
                }
            }
        }
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
