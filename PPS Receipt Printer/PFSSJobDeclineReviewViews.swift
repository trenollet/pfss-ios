//
//  PFSSJobDeclineReviewViews.swift
//  PPS Receipt Printer
//
//  Phase 19 Step 3 – Manager and Owner Job Review Required workflow.
//

import SwiftUI

struct PFSSJobDeclineReviewListView: View {
    @EnvironmentObject private var store: AppDataStore
    @ObservedObject private var center = PFSSJobDeclineReviewCenter.shared

    var body: some View {
        List {
            if center.pendingReviews.isEmpty {
                ContentUnavailableView(
                    "No Jobs Need Review",
                    systemImage: "checkmark.circle",
                    description: Text(
                        "Technician-declined jobs will appear here on every Manager and Owner device."
                    )
                )
            } else {
                ForEach(center.pendingReviews) { review in
                    NavigationLink {
                        PFSSJobDeclineReviewDetailView(review: review)
                            .environmentObject(store)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(customerName(for: review))
                                .font(.headline)
                            Text(review.jobNumber)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(review.reason)
                                .lineLimit(2)
                            Text(review.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Job Review Required")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            center.start()
            await center.refresh()
        }
        .refreshable { await center.refresh() }
    }

    private func customerName(for review: PFSSJobDeclineReview) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == review.customerNumber
        }) else { return review.customerNumber }
        return customer.businessName.isEmpty
            ? customer.contactName : customer.businessName
    }
}

struct PFSSJobDeclineReviewDetailView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var center = PFSSJobDeclineReviewCenter.shared

    let review: PFSSJobDeclineReview

    @State private var showingAssignmentManagement = false
    @State private var selectedAction = PFSSJobDeclineResolutionAction.returned
    @State private var resolutionNote = ""
    @State private var showingConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isResolving = false

    private var jobID: UUID? { UUID(uuidString: review.jobID) }
    private var assignmentID: UUID? { UUID(uuidString: review.assignmentID) }
    private var job: JobRecord? {
        guard let jobID else { return nil }
        return store.jobs.first { $0.id == jobID }
    }
    private var technicianName: String {
        guard let employeeID = UUID(uuidString: review.technicianEmployeeID) else {
            return "Technician"
        }
        return store.employees.first { $0.id == employeeID }?.displayName ?? "Technician"
    }
    private var customerName: String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == review.customerNumber
        }) else { return review.customerNumber }
        return customer.businessName.isEmpty
            ? customer.contactName : customer.businessName
    }

    var body: some View {
        Form {
            Section("Job") {
                LabeledContent("Customer", value: customerName)
                LabeledContent("Job", value: review.jobNumber)
                LabeledContent("Technician", value: technicianName)
                LabeledContent("Submitted") {
                    Text(review.createdAt.formatted(date: .long, time: .shortened))
                }
                if let job {
                    NavigationLink("Open Job") {
                        JobDetailView(job: job)
                            .environmentObject(store)
                    }
                }
            }

            Section("Technician Reason") {
                Text(review.reason)
            }

            Section("Take Action") {
                if assignmentID != nil {
                    Button {
                        showingAssignmentManagement = true
                    } label: {
                        Label("Manage Assignment", systemImage: "person.2.badge.gearshape")
                    }
                }
                Text(
                    "Reassign, reschedule, return, or cancel the work in Manage Assignment, then record the completed decision below."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Resolution") {
                Picker("Decision", selection: $selectedAction) {
                    ForEach(PFSSJobDeclineResolutionAction.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                TextField("Resolution note (optional)", text: $resolutionNote, axis: .vertical)
                Button {
                    showingConfirmation = true
                } label: {
                    Label("Complete Review", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isResolving)
            }
        }
        .navigationTitle("Review Declined Job")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAssignmentManagement) {
            if let assignmentID {
                DispatchBoardAssignmentActionsView(
                    assignmentID: assignmentID,
                    boardDate: job?.scheduledDate ?? Date()
                )
                .environmentObject(store)
            }
        }
        .confirmationDialog(
            "Complete this shared review as \(selectedAction.title)?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Complete Review") { resolve() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Unable to Complete Review", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func resolve() {
        isResolving = true
        Task {
            do {
                try await center.resolve(
                    review,
                    action: selectedAction,
                    note: resolutionNote
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isResolving = false
        }
    }
}
