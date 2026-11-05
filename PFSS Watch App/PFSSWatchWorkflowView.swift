import SwiftUI

struct PFSSWatchWorkflowView: View {
    @EnvironmentObject private var model: PFSSWatchWorkflowModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.snapshot.available {
                    Text(model.snapshot.customerName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(model.snapshot.jobNumber)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model.snapshot.state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    if let action = model.snapshot.primaryAction {
                        Button {
                            model.request(action)
                        } label: {
                            Label(action.title, systemImage: action.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(action == .completeJob ? .green : .orange)
                        .disabled(model.isSending)
                    }

                    ForEach(secondaryActions) { action in
                        Button {
                            model.request(action)
                        } label: {
                            Label(action.title, systemImage: action.icon)
                        }
                        .disabled(model.isSending)
                    }
                } else {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.title2)
                    Text(model.snapshot.message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { model.refresh() }
                }

                if model.isSending { ProgressView() }
                if model.snapshot.available, !model.snapshot.message.isEmpty {
                    Text(model.snapshot.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .confirmationDialog(
            "Complete this job?",
            isPresented: Binding(
                get: { model.confirmationAction != nil },
                set: { if !$0 { model.confirmationAction = nil } }
            )
        ) {
            Button("Complete Job", role: .destructive) { model.confirmAction() }
            Button("Cancel", role: .cancel) { model.confirmationAction = nil }
        }
    }

    private var secondaryActions: [PFSSWatchAction] {
        model.snapshot.actions.filter {
            $0 != model.snapshot.primaryAction &&
            [.pauseTravel, .resumeTravel, .pauseWork, .resumeWork].contains($0)
        }
    }
}
