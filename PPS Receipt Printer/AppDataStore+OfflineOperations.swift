//
//  AppDataStore+OfflineOperations.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 3 – Local-first workflow queue integration.
//

import Foundation

/// PFSS currently has no remote backend. Local-only mode prevents a false
/// backlog while keeping the operational boundary ready for a future adapter.
enum OfflineSynchronizationMode: String, Codable {
    case localOnly
    case queueRemoteOperations

    var requiresRemoteQueue: Bool {
        self == .queueRemoteOperations
    }
}

struct OfflineWorkflowActionPayload: Codable, Equatable {
    var jobID: UUID
    var jobNumber: String
    var action: String
    var employeeID: UUID?
    var note: String?
    var occurredAt: Date
    var resultingWorkflowState: String
}

struct OfflineTechnicianNotePayload: Codable, Equatable {
    var jobID: UUID
    var jobNumber: String
    var timelineEventID: UUID
    var employeeID: UUID?
    var text: String
    var occurredAt: Date
}

struct OfflineInvoiceStatusPayload: Codable, Equatable {
    var invoiceID: UUID
    var invoiceNumber: String
    var jobNumber: String
    var previousStatus: String
    var status: String
    var amountPaid: Double
    var balanceDue: Double
    var occurredAt: Date
}

struct OfflineRouteChangePayload: Codable, Equatable {
    var technicianID: UUID
    var orderedJobIDs: [UUID]
    var orderedAssignmentIDs: [UUID]
    var reason: String
    var occurredAt: Date
}

struct OfflineTimelineCorrectionPayload: Codable, Equatable {
    var jobID: UUID
    var jobNumber: String
    var eventID: UUID
    var originalTimestamp: Date
    var correctedTimestamp: Date
    var reason: String
    var actorEmployeeID: UUID
    var correctedAt: Date
}

@MainActor
extension AppDataStore {
    func enqueueTimelineCorrectionOperation(
        job: JobRecord,
        eventID: UUID,
        originalTimestamp: Date,
        correctedTimestamp: Date,
        reason: String,
        actorEmployeeID: UUID,
        correctedAt: Date
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue else { return }
        enqueueOfflineOperation(
            type: .jobTimestamp,
            entityType: .job,
            entityID: job.id,
            actionName: "correctTimelineTimestamp",
            actorEmployeeID: actorEmployeeID,
            value: OfflineTimelineCorrectionPayload(
                jobID: job.id,
                jobNumber: job.jobNumber,
                eventID: eventID,
                originalTimestamp: originalTimestamp,
                correctedTimestamp: correctedTimestamp,
                reason: reason,
                actorEmployeeID: actorEmployeeID,
                correctedAt: correctedAt
            ),
            createdAt: correctedAt,
            metadata: ["jobNumber": job.jobNumber]
        )
    }

    func enqueueWorkflowOperation(
        jobID: UUID,
        action: JobWorkflowAction,
        employeeID: UUID?,
        note: String?,
        timestamp: Date
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue,
              let job = jobs.first(where: { $0.id == jobID }) else { return }

        enqueueOfflineOperation(
            type: action == .createInvoice ? .invoiceHandoff : .workflowAction,
            entityType: .job,
            entityID: jobID,
            actionName: action.rawValue,
            actorEmployeeID: employeeID,
            value: OfflineWorkflowActionPayload(
                jobID: jobID,
                jobNumber: job.jobNumber,
                action: action.rawValue,
                employeeID: employeeID,
                note: normalizedOfflineNote(note),
                occurredAt: timestamp,
                resultingWorkflowState: job.workflowState.rawValue
            ),
            createdAt: timestamp,
            metadata: ["jobNumber": job.jobNumber]
        )
    }

    func enqueueTechnicianNoteOperation(
        jobID: UUID,
        event: JobTimelineEvent,
        text: String
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue,
              let job = jobs.first(where: { $0.id == jobID }) else { return }

        enqueueOfflineOperation(
            type: .jobNote,
            entityType: .job,
            entityID: jobID,
            actionName: "addTechnicianNote",
            actorEmployeeID: event.employeeID,
            value: OfflineTechnicianNotePayload(
                jobID: jobID,
                jobNumber: job.jobNumber,
                timelineEventID: event.id,
                employeeID: event.employeeID,
                text: text,
                occurredAt: event.timestamp
            ),
            createdAt: event.timestamp,
            metadata: ["jobNumber": job.jobNumber]
        )
    }

    func enqueueInvoiceOperation(
        invoice: InvoiceRecord,
        previousStatus: InvoiceStatus,
        timestamp: Date
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue else { return }

        let type: OfflineOperationType
        switch invoice.status {
        case .partiallyPaid, .paid:
            type = .paymentRecording
        case .sent, .overdue:
            type = .invoiceHandoff
        case .draft, .void:
            type = .recordMutation
        }

        enqueueOfflineOperation(
            type: type,
            entityType: .invoice,
            entityID: invoice.id,
            actionName: "invoiceStatusChanged",
            actorEmployeeID: jobs.first(where: {
                $0.jobNumber == invoice.jobNumber
            })?.primaryTechnicianID,
            value: OfflineInvoiceStatusPayload(
                invoiceID: invoice.id,
                invoiceNumber: invoice.invoiceNumber,
                jobNumber: invoice.jobNumber,
                previousStatus: previousStatus.rawValue,
                status: invoice.status.rawValue,
                amountPaid: invoice.amountPaid,
                balanceDue: invoice.balanceDue,
                occurredAt: timestamp
            ),
            createdAt: timestamp,
            metadata: [
                "invoiceNumber": invoice.invoiceNumber,
                "jobNumber": invoice.jobNumber
            ]
        )
    }

    func enqueueRouteChangeOperation(
        technicianID: UUID,
        orderedJobIDs: [UUID],
        orderedAssignmentIDs: [UUID],
        reason: String,
        timestamp: Date
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue else { return }

        enqueueOfflineOperation(
            type: .routeChange,
            entityType: .employee,
            entityID: technicianID,
            actionName: "routeOrderChanged",
            actorEmployeeID: technicianID,
            value: OfflineRouteChangePayload(
                technicianID: technicianID,
                orderedJobIDs: orderedJobIDs,
                orderedAssignmentIDs: orderedAssignmentIDs,
                reason: reason,
                occurredAt: timestamp
            ),
            createdAt: timestamp,
            metadata: ["stopCount": String(orderedJobIDs.count)]
        )
    }

    private func enqueueOfflineOperation<Value: Encodable>(
        type: OfflineOperationType,
        entityType: OfflineEntityType,
        entityID: UUID?,
        actionName: String,
        actorEmployeeID: UUID?,
        value: Value,
        createdAt: Date,
        metadata: [String: String]
    ) {
        do {
            let payload = try OfflineOperationPayload(value)
            let operation = PendingOfflineOperation(
                type: type,
                entityType: entityType,
                entityID: entityID,
                actionName: actionName,
                actorEmployeeID: actorEmployeeID,
                payload: payload,
                createdAt: createdAt,
                metadata: metadata
            )
            _ = try offlineOperationQueue.enqueue(operation)
            lastOfflineOperationError = nil
        } catch {
            // The local mutation is already safely persisted. Surface queue
            // failure for Part 6 UI without rolling back technician work.
            lastOfflineOperationError = error.localizedDescription
        }
    }

    private func normalizedOfflineNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
