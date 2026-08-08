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

struct OfflineRecordMutationPayload: Codable, Equatable {
    var entityType: OfflineEntityType
    var entityID: UUID
    var recordData: Data
    var modifiedAt: Date
}

@MainActor
extension AppDataStore {
    func applyServerConflictResolutionReceipts(
        _ receipts: [PFSSCloudflareConflictResolutionReceipt]
    ) {
        for receipt in receipts {
            synchronizedRecordRevisions[
                synchronizationKey(
                    type: receipt.entityType,
                    id: receipt.entityID
                )
            ] = receipt.finalRevision
            for queued in offlineOperationQueue.operations where
                queued.type == .recordMutation &&
                queued.entityType == receipt.entityType &&
                queued.entityID == receipt.entityID &&
                queued.createdAt >= receipt.resolvedAt &&
                [.pending, .waitingForRetry, .failed].contains(queued.status) {
                try? offlineOperationQueue.mutate(id: queued.id) {
                    $0.baseRevision = receipt.finalRevision
                }
            }
            guard let local = offlineOperationQueue.operations.first(where: {
                $0.status == .conflicted &&
                $0.metadata["serverConflictID"] == receipt.id
            }) else { continue }
            let resolution: OfflineConflictResolution
            switch receipt.resolution {
            case "keptCloud": resolution = .keptRemote
            case "keptDevice": resolution = .keptLocal
            default: continue
            }
            try? OfflineConflictResolutionService(
                queue: offlineOperationQueue
            ).resolve(
                operationID: local.id,
                resolution: resolution,
                employeeID: nil,
                note: "Resolved by a Manager or Owner in the PFSS conflict inbox.",
                at: receipt.resolvedAt,
                resubmitLocal: false
            )
        }
        saveSynchronizedRecordRevisions()
    }

    func reconcileServerConflictInbox(
        _ serverConflicts: [PFSSCloudflareSynchronizationConflict]
    ) throws {
        let activeIDs = Set(serverConflicts.map(\.id))
        for operation in offlineOperationQueue.operations {
            if let conflictID = operation.metadata["serverConflictID"],
               !activeIDs.contains(conflictID) {
                try offlineOperationQueue.remove(id: operation.id)
            }
        }

        for serverConflict in serverConflicts {
            guard !offlineOperationQueue.operations.contains(where: {
                $0.metadata["serverConflictID"] == serverConflict.id
            }) else { continue }

            var operation = serverConflict.localOperation
            operation.id = UUID(uuidString: serverConflict.id) ?? UUID()
            operation.idempotencyKey = "server-conflict-\(serverConflict.id)"
            operation.sequenceNumber = 0
            operation.status = .conflicted
            operation.updatedAt = serverConflict.detectedAt
            operation.failure = OfflineFailureDetails(
                category: .conflict,
                code: "manager_review_required",
                message: "A team member's change requires Manager or Owner review.",
                isRetryable: false,
                occurredAt: serverConflict.detectedAt
            )
            operation.conflict = OfflineConflictInformation(
                id: operation.id,
                kind: .concurrentModification,
                detectedAt: serverConflict.detectedAt,
                localVersion: OfflineRecordVersion(
                    revision: operation.baseRevision,
                    modifiedAt: operation.createdAt,
                    source: .local,
                    payload: operation.payload
                ),
                remoteVersion: OfflineRecordVersion(
                    revision: serverConflict.cloudRevision,
                    modifiedAt: serverConflict.cloudOperation.createdAt,
                    source: .remote,
                    payload: serverConflict.cloudOperation.payload
                )
            )
            operation.metadata["serverConflictID"] = serverConflict.id
            operation.metadata["sourceMemberID"] = serverConflict.sourceMemberID
            operation.metadata["sourceDeviceID"] = serverConflict.sourceDeviceID
            try offlineOperationQueue.enqueue(operation)
        }
    }

    func resolveInboxConflict(
        operationID: UUID,
        resolution: OfflineConflictResolution,
        reason: String,
        affectedFields: [String]
    ) async throws {
        guard let operation = offlineOperationQueue.operation(id: operationID),
              let conflictID = operation.metadata["serverConflictID"],
              let requestResolution = onServerConflictResolutionRequested else {
            throw OfflineConflictResolutionError.operationNotFound
        }
        let receipt = try await requestResolution(
            conflictID,
            resolution,
            reason,
            affectedFields
        )

        var selected = operation
        if resolution == .keptRemote,
           let remote = operation.conflict?.remoteVersion {
            selected.payload = remote.payload
        }
        selected.metadata["remoteRevision"] = receipt.finalRevision
        applyRemoteRecordOperations([selected])

        try OfflineConflictResolutionService(queue: offlineOperationQueue).resolve(
            operationID: operationID,
            resolution: resolution,
            employeeID: operation.actorEmployeeID,
            note: "Resolved from the tenant Manager conflict inbox.",
            resubmitLocal: false
        )
    }

    func resolveRecordConflict(
        operationID: UUID,
        resolution: OfflineConflictResolution,
        note: String = "Resolved from PFSS synchronization review."
    ) throws {
        guard let operation = offlineOperationQueue.operation(id: operationID),
              let conflict = operation.conflict else {
            throw OfflineConflictResolutionError.operationNotFound
        }

        if resolution == .keptRemote,
           let remoteVersion = conflict.remoteVersion {
            var remoteOperation = operation
            remoteOperation.payload = remoteVersion.payload
            if let revision = remoteVersion.revision {
                remoteOperation.metadata["remoteRevision"] = revision
            }
            applyRemoteRecordOperations([remoteOperation])
        }

        try OfflineConflictResolutionService(queue: offlineOperationQueue).resolve(
            operationID: operationID,
            resolution: resolution,
            employeeID: operation.actorEmployeeID,
            note: note
        )
        if resolution == .keptLocal {
            offlineSynchronizationService?.syncNow()
        }
    }

    func applyRemoteRecordOperations(_ operations: [PendingOfflineOperation]) {
        applyRemoteConflictResolutionReceipts(operations)
        let recordOperations = operations.filter {
            $0.type == .recordMutation && $0.actionName == "upsertRecord"
        }
        guard !recordOperations.isEmpty else { return }

        isApplyingRemoteSynchronization = true
        defer {
            synchronizedRecordState = makeSynchronizedRecordState()
            isApplyingRemoteSynchronization = false
        }

        for operation in recordOperations {
            guard let mutation = try? operation.payload.decode(
                OfflineRecordMutationPayload.self,
                decoder: Self.recordSynchronizationDecoder
            ) else { continue }
            applyRemoteRecordMutation(mutation)
            if let revision = operation.metadata["remoteRevision"] {
                synchronizedRecordRevisions[
                    synchronizationKey(
                        type: mutation.entityType,
                        id: mutation.entityID
                    )
                ] = revision
            }
        }
        relinkActiveOperationsToAuthenticatedEmployeeIfNeeded()
        saveSynchronizedRecordRevisions()
    }

    /// Repairs operational references created before a cloud membership was
    /// linked to its canonical Employee record. Historical timeline and crew
    /// entries remain unchanged; only live work ownership is relinked.
    func relinkActiveOperationsToAuthenticatedEmployeeIfNeeded() {
        guard let canonicalID = cloudEmployeeID,
              let canonical = employees.first(where: { $0.id == canonicalID }) else {
            return
        }

        let canonicalEmail = Self.normalizedEmployeeIdentityEmail(canonical.email)
        guard !canonicalEmail.isEmpty else { return }

        let legacyIDs = Set(employees.compactMap { employee -> UUID? in
            guard employee.id != canonicalID,
                  Self.normalizedEmployeeIdentityEmail(employee.email) == canonicalEmail,
                  !employee.isActive || employee.lifecycleStatus == .archived else {
                return nil
            }
            return employee.id
        })
        guard !legacyIDs.isEmpty else { return }

        var repairedJobs = jobs
        var repairedJobIDs = Set<UUID>()
        for index in repairedJobs.indices where
            repairedJobs[index].lifecycleStatus == .active &&
            repairedJobs[index].status != .completed &&
            repairedJobs[index].status != .cancelled {
            var changed = false
            if let technicianID = repairedJobs[index].primaryTechnicianID,
               legacyIDs.contains(technicianID) {
                repairedJobs[index].primaryTechnicianID = canonicalID
                changed = true
            }
            if let technicianID = repairedJobs[index].secondaryTechnicianID,
               legacyIDs.contains(technicianID) {
                repairedJobs[index].secondaryTechnicianID = canonicalID
                changed = true
            }
            if changed {
                repairedJobIDs.insert(repairedJobs[index].id)
            }
        }

        var repairedAssignments = assignmentStore.assignments
        var repairedAssignmentIDs = Set<UUID>()
        for assignmentIndex in repairedAssignments.indices where
            repairedAssignments[assignmentIndex].isOperationallyActive {
            let alreadyContainsCanonical = repairedAssignments[assignmentIndex]
                .crew.activeMembers.contains { $0.employeeID == canonicalID }
            for memberIndex in repairedAssignments[assignmentIndex].crew.members.indices {
                guard repairedAssignments[assignmentIndex].crew.members[memberIndex].isActive,
                      legacyIDs.contains(
                        repairedAssignments[assignmentIndex].crew.members[memberIndex].employeeID
                      ) else { continue }
                if alreadyContainsCanonical {
                    repairedAssignments[assignmentIndex].crew.members[memberIndex].removedDate = Date()
                } else {
                    repairedAssignments[assignmentIndex].crew.members[memberIndex].employeeID = canonicalID
                }
                repairedAssignmentIDs.insert(repairedAssignments[assignmentIndex].id)
            }
        }

        guard !repairedJobIDs.isEmpty || !repairedAssignmentIDs.isEmpty else { return }

        let wasApplyingRemoteSynchronization = isApplyingRemoteSynchronization
        isApplyingRemoteSynchronization = true
        defer {
            synchronizedRecordState = makeSynchronizedRecordState()
            isApplyingRemoteSynchronization = wasApplyingRemoteSynchronization
        }

        if !repairedAssignmentIDs.isEmpty {
            try? assignmentStore.replaceAll(with: repairedAssignments)
        }
        if !repairedJobIDs.isEmpty {
            jobs = repairedJobs
        }
    }

    private static func normalizedEmployeeIdentityEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func applyRemoteConflictResolutionReceipts(
        _ operations: [PendingOfflineOperation]
    ) {
        for receipt in operations {
            guard let conflictID = receipt.metadata["serverConflictID"],
                  let resolutionValue =
                    receipt.metadata["conflictResolution"],
                  let local = offlineOperationQueue.operations.first(where: {
                      $0.status == .conflicted &&
                      $0.metadata["serverConflictID"] == conflictID
                  }) else { continue }
            let resolution: OfflineConflictResolution
            switch resolutionValue {
            case "keptLocal": resolution = .keptLocal
            case "keptRemote": resolution = .keptRemote
            default: continue
            }
            try? OfflineConflictResolutionService(
                queue: offlineOperationQueue
            ).resolve(
                operationID: local.id,
                resolution: resolution,
                employeeID: receipt.actorEmployeeID,
                note: "Resolved by a Manager or Owner in the PFSS conflict inbox.",
                resubmitLocal: false
            )
        }
    }

    private func applyRemoteRecordMutation(_ mutation: OfflineRecordMutationPayload) {
        switch mutation.entityType {
        case .customer:
            Self.upsertRemote(decodeRemote(Customer.self, mutation), in: &customers)
        case .site:
            Self.upsertRemote(decodeRemote(CustomerSite.self, mutation), in: &sites)
        case .lead:
            Self.upsertRemote(decodeRemote(Lead.self, mutation), in: &leads)
        case .estimate:
            Self.upsertRemote(decodeRemote(EstimateRecord.self, mutation), in: &estimates)
        case .job:
            Self.upsertRemote(decodeRemote(JobRecord.self, mutation), in: &jobs)
        case .invoice:
            Self.upsertRemote(decodeRemote(InvoiceRecord.self, mutation), in: &invoices)
        case .employee:
            Self.upsertRemote(decodeRemote(EmployeeRecord.self, mutation), in: &employees)
        case .catalog:
            Self.upsertRemote(decodeRemote(ServiceCatalogItem.self, mutation), in: &serviceCatalogItems)
        case .assignment:
            guard let assignment = decodeRemote(Assignment.self, mutation) else { return }
            var assignments = assignmentStore.assignments
            if let index = assignments.firstIndex(where: { $0.id == assignment.id }) {
                assignments[index] = assignment
            } else {
                assignments.append(assignment)
            }
            try? assignmentStore.replaceAll(with: assignments)
        case .recurringWork:
            Self.upsertRemote(
                decodeRemote(RecurringWorkTemplate.self, mutation),
                in: &recurringWorkTemplates
            )
            materializeRecurringWorkHorizon()
        case .payment, .route, .custom:
            break
        }
    }

    private func decodeRemote<Value: Decodable>(
        _ type: Value.Type,
        _ mutation: OfflineRecordMutationPayload
    ) -> Value? {
        try? Self.recordSynchronizationDecoder.decode(type, from: mutation.recordData)
    }

    private static func upsertRemote<Value: Identifiable>(
        _ value: Value?,
        in values: inout [Value]
    ) where Value.ID == UUID {
        guard let value else { return }
        if let index = values.firstIndex(where: { $0.id == value.id }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }

    func enqueueRecordMutation<Value: Encodable>(
        entityType: OfflineEntityType,
        entityID: UUID,
        value: Value,
        modifiedAt: Date = Date()
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue else { return }
        do {
            let recordData = try Self.recordSynchronizationEncoder.encode(value)
            let mutation = OfflineRecordMutationPayload(
                entityType: entityType,
                entityID: entityID,
                recordData: recordData,
                modifiedAt: modifiedAt
            )
            let payload = try OfflineOperationPayload(
                mutation,
                encoder: Self.recordSynchronizationEncoder
            )
            let operation = PendingOfflineOperation(
                type: .recordMutation,
                entityType: entityType,
                entityID: entityID,
                actionName: "upsertRecord",
                actorEmployeeID: nil,
                payload: payload,
                createdAt: modifiedAt,
                baseRevision: synchronizedRecordRevisions[
                    synchronizationKey(type: entityType, id: entityID)
                ],
                metadata: ["recordSync": "true"]
            )
            _ = try offlineOperationQueue.enqueue(operation)
            lastOfflineOperationError = nil
        } catch {
            lastOfflineOperationError = error.localizedDescription
        }
    }

    static let recordSynchronizationEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let recordSynchronizationDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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
