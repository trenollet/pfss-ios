import SwiftUI

struct AssignmentSchedulingEditorView: View {
    @ObservedObject var engine: AssignmentEngine

    let assignmentID: UUID
    let actorEmployeeID: UUID?

    @Environment(\.dismiss) private var dismiss

    @State private var mode: AssignmentSchedulingMode
    @State private var serviceDate: Date
    @State private var fixedStartDate: Date
    @State private var arrivalWindowStart: Date
    @State private var arrivalWindowEnd: Date
    @State private var completionDeadline: Date
    @State private var estimatedDurationMinutes: Int
    @State private var preServiceBufferMinutes: Int
    @State private var postServiceBufferMinutes: Int
    @State private var isCustomerConfirmed: Bool
    @State private var schedulingNotes: String
    @State private var errorMessage = ""
    @State private var showingError = false

    init(
        engine: AssignmentEngine,
        assignmentID: UUID,
        scheduling: AssignmentScheduling,
        actorEmployeeID: UUID? = nil
    ) {
        self.engine = engine
        self.assignmentID = assignmentID
        self.actorEmployeeID = actorEmployeeID

        let now = QuarterHourDatePicker.normalized(Date())
        _mode = State(initialValue: scheduling.mode)
        _serviceDate = State(initialValue: scheduling.serviceDate ?? now)
        _fixedStartDate = State(initialValue: scheduling.fixedStartDate ?? now)
        _arrivalWindowStart = State(initialValue: scheduling.arrivalWindowStart ?? now)
        _arrivalWindowEnd = State(
            initialValue: scheduling.arrivalWindowEnd ??
                Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now
        )
        _completionDeadline = State(initialValue: scheduling.completionDeadline ?? now)
        _estimatedDurationMinutes = State(initialValue: max(scheduling.estimatedDurationMinutes, 15))
        _preServiceBufferMinutes = State(initialValue: scheduling.preServiceBufferMinutes)
        _postServiceBufferMinutes = State(initialValue: scheduling.postServiceBufferMinutes)
        _isCustomerConfirmed = State(initialValue: scheduling.isCustomerConfirmed)
        _schedulingNotes = State(initialValue: scheduling.schedulingNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scheduling Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(AssignmentSchedulingMode.allCases) { schedulingMode in
                            Text(schedulingMode.rawValue).tag(schedulingMode)
                        }
                    }

                    Text(mode.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Schedule") {
                    schedulingFields
                }

                Section("Planning") {
                    Stepper(
                        "Estimated Duration: \(durationText(estimatedDurationMinutes))",
                        value: $estimatedDurationMinutes,
                        in: 15...720,
                        step: 15
                    )

                    Stepper(
                        "Pre-service Buffer: \(preServiceBufferMinutes) min",
                        value: $preServiceBufferMinutes,
                        in: 0...120,
                        step: 5
                    )

                    Stepper(
                        "Post-service Buffer: \(postServiceBufferMinutes) min",
                        value: $postServiceBufferMinutes,
                        in: 0...120,
                        step: 5
                    )

                    Toggle("Customer Confirmed", isOn: $isCustomerConfirmed)
                }

                Section("Scheduling Notes") {
                    TextField(
                        "Optional scheduling instructions",
                        text: $schedulingNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                if proposedScheduling.validationIssues.isEmpty == false {
                    Section("Needs Attention") {
                        ForEach(proposedScheduling.validationIssues, id: \.self) { issue in
                            Label(issue.rawValue, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Assignment Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(proposedScheduling.isValid == false)
                }
            }
            .alert("Schedule Update", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var schedulingFields: some View {
        switch mode {
        case .fixedTime:
            QuarterHourDatePicker(
                selection: $fixedStartDate,
                dateLabel: "Service Date",
                timeLabel: "Start Time"
            )

        case .arrivalWindow:
            QuarterHourDatePicker(
                selection: $arrivalWindowStart,
                dateLabel: "Service Date",
                timeLabel: "Earliest Arrival"
            )
            QuarterHourDatePicker(
                selection: $arrivalWindowEnd,
                dateLabel: "Window End Date",
                timeLabel: "Latest Arrival"
            )

        case .flexibleDay:
            DatePicker(
                "Service Date",
                selection: $serviceDate,
                displayedComponents: .date
            )

        case .deadline:
            QuarterHourDatePicker(
                selection: $completionDeadline,
                dateLabel: "Deadline Date",
                timeLabel: "Complete By"
            )
        }
    }

    private var proposedScheduling: AssignmentScheduling {
        AssignmentScheduling(
            mode: mode,
            serviceDate: serviceDateForMode,
            fixedStartDate: mode == .fixedTime
                ? QuarterHourDatePicker.normalized(fixedStartDate)
                : nil,
            arrivalWindowStart: mode == .arrivalWindow
                ? QuarterHourDatePicker.normalized(arrivalWindowStart)
                : nil,
            arrivalWindowEnd: mode == .arrivalWindow
                ? QuarterHourDatePicker.normalized(arrivalWindowEnd)
                : nil,
            completionDeadline: mode == .deadline
                ? QuarterHourDatePicker.normalized(completionDeadline)
                : nil,
            estimatedDurationMinutes: estimatedDurationMinutes,
            preServiceBufferMinutes: preServiceBufferMinutes,
            postServiceBufferMinutes: postServiceBufferMinutes,
            isCustomerConfirmed: isCustomerConfirmed,
            schedulingNotes: schedulingNotes
        )
    }

    private var serviceDateForMode: Date? {
        switch mode {
        case .fixedTime:
            return fixedStartDate
        case .arrivalWindow:
            return arrivalWindowStart
        case .flexibleDay:
            return serviceDate
        case .deadline:
            return nil
        }
    }

    private func save() {
        do {
            _ = try engine.reschedule(
                assignmentID: assignmentID,
                scheduling: proposedScheduling,
                actorEmployeeID: actorEmployeeID,
                note: "Scheduling updated from Assignment Detail"
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }
}
