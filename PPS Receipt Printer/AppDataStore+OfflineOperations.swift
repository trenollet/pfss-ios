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

/// Early record-mutation envelopes sometimes omitted the duplicate inner
/// entity ID even though the durable operation retained the authoritative ID.
/// This shape is accepted only while rebuilding from server canonical state.
private struct LegacyCanonicalRecordMutationPayload: Decodable {
    var entityType: OfflineEntityType
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
                    if let payload = try? OfflineRecordMutationCodec
                        .rebasingBaseRevision(
                            $0.payload,
                            to: receipt.finalRevision,
                            decoder: Self.recordSynchronizationDecoder,
                            encoder: Self.recordSynchronizationEncoder
                        ) {
                        $0.payload = payload
                        $0.baseRevision = receipt.finalRevision
                    }
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
            if let affectedFields = serverConflict.affectedFields,
               !affectedFields.isEmpty {
                operation.metadata["conflictingPaths"] = affectedFields.joined(separator: ",")
            }
            if let operationalImpact = serverConflict.operationalImpact {
                operation.metadata["conflictOperationalImpact"] = operationalImpact
            }
            if let policyVersion = serverConflict.policyVersion {
                operation.metadata["conflictPolicyVersion"] = policyVersion.formatted()
            }
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

    func discardRevokedDeviceConflicts(
        sourceDeviceID: String,
        expectedCount: Int
    ) async throws {
        guard canOverrideSynchronizationConflicts,
              let requestCleanup = onRevokedDeviceConflictCleanupRequested else {
            throw OfflineConflictResolutionError.invalidResolution
        }
        let receipt = try await requestCleanup(
            sourceDeviceID,
            expectedCount,
            "Discarded retained changes after the source device was revoked."
        )
        guard receipt.resolvedCount > 0,
              receipt.sourceDeviceID == sourceDeviceID,
              receipt.resolution == "keptCloud" else {
            throw OfflineConflictResolutionError.invalidResolution
        }
        for operation in offlineOperationQueue.operations where
            operation.status == .conflicted &&
            operation.metadata["sourceDeviceID"] == sourceDeviceID {
            try? offlineOperationQueue.remove(id: operation.id)
        }
    }

    func applyServerQuarantineResolutionReceipts(
        _ receipts: [PFSSCloudflareQuarantineResolutionReceipt]
    ) {
        for receipt in receipts {
            guard let operation = offlineOperationQueue.operation(
                id: receipt.operationID
            ) ?? offlineOperationQueue.operations.first(where: {
                $0.metadata["serverQuarantineID"] == receipt.id
            }) else { continue }
            let wasAlreadyFinalized =
                operation.metadata["appliedQuarantineResolutionID"] == receipt.id &&
                (receipt.action == "retry" || operation.status == .cancelled)
            guard !wasAlreadyFinalized else { continue }
            let localOperationID = operation.id
            let resolution: OfflineQuarantineResolution = receipt.action == "retry"
                ? .retry
                : .discard
            do {
                try offlineOperationQueue.resolveQuarantinedOperation(
                    id: localOperationID,
                    resolution: resolution,
                    reason: receipt.reason
                        ?? "Resolved by a Manager or Owner in the quarantine inbox.",
                    at: receipt.resolvedAt
                )
                try offlineOperationQueue.mutate(id: localOperationID) {
                    $0.metadata["appliedQuarantineResolutionID"] = receipt.id
                    if receipt.action == "retry" {
                        $0.metadata.removeValue(forKey: "serverQuarantineID")
                        $0.metadata.removeValue(forKey: "quarantineDeliveryStatus")
                        $0.metadata.removeValue(forKey: "quarantineDeliveryError")
                    }
                }
            } catch {
                // Leave the receipt eligible for the next synchronization poll.
            }
        }
        if receipts.contains(where: { $0.action == "retry" }) {
            offlineSynchronizationService?.syncNow()
        }
    }

    func reconcileServerQuarantineInbox(
        _ serverItems: [PFSSCloudflareSynchronizationQuarantine]
    ) throws {
        let activeIDs = Set(serverItems.map(\.id))
        for operation in offlineOperationQueue.operations {
            if let quarantineID = operation.metadata["serverQuarantineID"],
               !activeIDs.contains(quarantineID) {
                try offlineOperationQueue.remove(id: operation.id)
            }
        }
        for item in serverItems {
            var authoritativeOperation = item.operation
            if let envelope = try? item.operation.payload.decode(
                SynchronizationMutationEnvelope.self,
                decoder: Self.recordSynchronizationDecoder
            ), envelope.schemaVersion >= SynchronizationMutationEnvelope.currentSchemaVersion,
               envelope.operationID != authoritativeOperation.id {
                authoritativeOperation.id = envelope.operationID
                authoritativeOperation.idempotencyKey =
                    "pfss-operation-\(envelope.operationID.uuidString.lowercased())"
            }
            if let existing = offlineOperationQueue.operations.first(where: {
                $0.metadata["serverQuarantineID"] == item.id ||
                    $0.id == authoritativeOperation.id ||
                    $0.id == item.operationID ||
                    $0.metadata["sourceOperationID"] ==
                        item.operationID.uuidString.lowercased()
            }) {
                if existing.id != authoritativeOperation.id {
                    try offlineOperationQueue.remove(id: existing.id)
                } else {
                try offlineOperationQueue.mutate(id: existing.id) { operation in
                    operation.status = .failed
                    operation.updatedAt = item.detectedAt
                    operation.failure = OfflineFailureDetails(
                        category: .validation,
                        code: "manager_quarantine_review_required",
                        message: item.failure.reason,
                        isRetryable: false,
                        occurredAt: item.detectedAt
                    )
                    operation.metadata["serverQuarantineStatus"] = "unresolved"
                    operation.metadata["serverQuarantineID"] = item.id
                    operation.metadata["sourceOperationID"] =
                        item.operationID.uuidString.lowercased()
                    operation.metadata["sourceMemberID"] = item.sourceMemberID
                    operation.metadata["sourceDeviceID"] = item.sourceDeviceID
                    operation.metadata.removeValue(forKey: "quarantineResolvedAt")
                    operation.metadata.removeValue(forKey: "quarantineResolution")
                    operation.metadata.removeValue(forKey: "quarantineResolutionReason")
                }
                continue
                }
            }
            var operation = authoritativeOperation
            operation.sequenceNumber = 0
            operation.status = .failed
            operation.updatedAt = item.detectedAt
            operation.failure = OfflineFailureDetails(
                category: .validation,
                code: "manager_quarantine_review_required",
                message: item.failure.reason,
                isRetryable: false,
                occurredAt: item.detectedAt
            )
            if let cloud = item.cloudOperation {
                operation.conflict = OfflineConflictInformation(
                    id: operation.id,
                    kind: .concurrentModification,
                    detectedAt: item.detectedAt,
                    localVersion: OfflineRecordVersion(
                        revision: operation.baseRevision,
                        modifiedAt: operation.createdAt,
                        source: .local,
                        payload: operation.payload
                    ),
                    remoteVersion: OfflineRecordVersion(
                        revision: item.cloudRevision,
                        modifiedAt: cloud.createdAt,
                        source: .remote,
                        payload: cloud.payload
                    )
                )
            }
            operation.metadata["serverQuarantineID"] = item.id
            operation.metadata["serverQuarantineStatus"] = "unresolved"
            operation.metadata["sourceOperationID"] =
                item.operationID.uuidString.lowercased()
            operation.metadata["sourceMemberID"] = item.sourceMemberID
            operation.metadata["sourceDeviceID"] = item.sourceDeviceID
            operation.metadata["quarantineReason"] = item.failure.reason
            operation.metadata["quarantinedAt"] = ISO8601DateFormatter()
                .string(from: item.detectedAt)
            operation.metadata["quarantineAffectedFields"] =
                item.affectedFields.joined(separator: ",")
            operation.metadata["quarantineOperationalImpact"] =
                item.operationalImpact
            operation.metadata["quarantinePolicyVersion"] =
                item.policyVersion.formatted()
            try offlineOperationQueue.enqueue(operation)
        }
    }

    func resolveInboxQuarantine(
        operationID: UUID,
        resolution: OfflineQuarantineResolution,
        reason: String
    ) async throws {
        guard let operation = offlineOperationQueue.operation(id: operationID),
              let quarantineID = operation.metadata["serverQuarantineID"],
              let requestResolution = onServerQuarantineResolutionRequested
        else { throw OfflineOperationQueueError.operationNotFound(operationID) }
        _ = try await requestResolution(quarantineID, resolution, reason)
        try offlineOperationQueue.remove(id: operationID)
    }

    func repairAssignmentQuarantine(
        operationID: UUID,
        repairedAssignment: Assignment,
        reason: String
    ) async throws {
        guard canOverrideSynchronizationConflicts,
              let quarantined = offlineOperationQueue.operation(id: operationID),
              quarantined.entityType == .assignment,
              quarantined.entityID == repairedAssignment.id,
              let quarantineID = quarantined.metadata["serverQuarantineID"],
              let remote = quarantined.conflict?.remoteVersion,
              let submitRepair = onServerQuarantineRepairRequested
        else { throw OfflineOperationQueueError.operationNotFound(operationID) }
        let validation = assignmentEngine.validateAssignment(repairedAssignment)
        guard validation.state != .invalid else {
            throw NSError(
                domain: "PFSSAssignmentRepair",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    validation.messages.joined(separator: " ")]
            )
        }
        let remoteMutation = try OfflineRecordMutationCodec.decode(
            remote.payload,
            decoder: Self.recordSynchronizationDecoder
        )
        let repairedData = try Self.recordSynchronizationEncoder.encode(
            repairedAssignment
        )
        let classification = SynchronizationMutationClassifier.classify(
            entityType: .assignment,
            baseRecordData: remoteMutation.recordData,
            recordData: repairedData
        )
        let replacementID = UUID()
        let now = Date()
        let payload = try OfflineRecordMutationCodec.envelopePayload(
            operationID: replacementID,
            entityType: .assignment,
            entityID: repairedAssignment.id,
            recordData: repairedData,
            baseRecordData: remoteMutation.recordData,
            modifiedAt: now,
            baseRevision: remote.revision,
            mutationKind: classification.kind,
            changedFields: classification.changedFields,
            commandName: classification.commandName,
            actorEmployeeID: cloudEmployeeID,
            encoder: Self.recordSynchronizationEncoder
        )
        var replacement = PendingOfflineOperation(
            id: replacementID,
            type: .recordMutation,
            entityType: .assignment,
            entityID: repairedAssignment.id,
            actionName: "upsertRecord",
            actorEmployeeID: cloudEmployeeID,
            payload: payload,
            createdAt: now,
            baseRevision: remote.revision,
            metadata: [
                "recordSync": "true",
                "mutationEnvelopeVersion": String(
                    SynchronizationMutationEnvelope.currentSchemaVersion
                ),
                "mutationKind": classification.kind.rawValue,
                "changedFields": classification.changedFields.joined(separator: ","),
                "commandName": classification.commandName ?? "",
                "repairedQuarantineID": quarantineID,
                "replacesOperationID": quarantined.metadata["sourceOperationID"]
                    ?? ""
            ]
        )
        let revision = try await submitRepair(quarantineID, replacement, reason)
        replacement.status = .synchronized
        replacement.metadata["remoteRevision"] = revision
        applyRemoteRecordOperations([replacement])
        try offlineOperationQueue.remove(id: operationID)
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
            guard let mutation = try? OfflineRecordMutationCodec.decode(
                operation.payload,
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

    /// Replaces every server-synchronized record family with the canonical
    /// tenant baseline. Archive-only settings remain available, while records
    /// absent from server authority cannot survive as stale local additions.
    func applyAuthoritativeCanonicalBaseline(
        _ operations: [PendingOfflineOperation]
    ) {
        let recordOperations = operations.filter {
            $0.type == .recordMutation && $0.actionName == "upsertRecord"
        }

        // The protected archive is the compatibility fallback for canonical
        // records written by an older app schema. Only records whose IDs are
        // still present in server authority may survive through this fallback.
        let fallbackCustomers = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })
        let fallbackSites = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
        let fallbackLeads = Dictionary(uniqueKeysWithValues: leads.map { ($0.id, $0) })
        let fallbackEstimates = Dictionary(uniqueKeysWithValues: estimates.map { ($0.id, $0) })
        let fallbackJobs = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        let fallbackInvoices = Dictionary(uniqueKeysWithValues: invoices.map { ($0.id, $0) })
        let fallbackEmployees = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
        let fallbackCatalog = Dictionary(uniqueKeysWithValues: serviceCatalogItems.map { ($0.id, $0) })
        let fallbackRecurring = Dictionary(uniqueKeysWithValues: recurringWorkTemplates.map { ($0.id, $0) })
        let fallbackAssignments = Dictionary(
            uniqueKeysWithValues: assignmentStore.assignments.map { ($0.id, $0) }
        )
        let fallbackBusinessProfile = businessProfile

        isApplyingRestoredSnapshot = true
        isApplyingRemoteSynchronization = true
        defer { isApplyingRemoteSynchronization = false }

        customers = []
        sites = []
        leads = []
        estimates = []
        jobs = []
        invoices = []
        employees = []
        serviceCatalogItems = []
        recurringWorkTemplates = []
        businessProfile = BusinessProfile()
        try? assignmentStore.replaceAll(with: [])
        var canonicalAssignments: [Assignment] = []

        for operation in recordOperations {
            let mutation: OfflineRecordMutationPayload
            if let decoded = try? OfflineRecordMutationCodec.decode(
                operation.payload,
                decoder: Self.recordSynchronizationDecoder
            ) {
                mutation = decoded
            } else if let entityID = operation.entityID,
                      let legacy = try? operation.payload.decode(
                        LegacyCanonicalRecordMutationPayload.self,
                        decoder: Self.recordSynchronizationDecoder
                      ) {
                mutation = OfflineRecordMutationPayload(
                    entityType: legacy.entityType,
                    entityID: entityID,
                    recordData: legacy.recordData,
                    modifiedAt: legacy.modifiedAt
                )
            } else {
                continue
            }
            switch mutation.entityType {
            case .customer:
                Self.upsertRemote(
                    decodeRemote(Customer.self, mutation) ?? fallbackCustomers[mutation.entityID],
                    in: &customers
                )
            case .site:
                Self.upsertRemote(
                    decodeRemote(CustomerSite.self, mutation) ?? fallbackSites[mutation.entityID],
                    in: &sites
                )
            case .lead:
                Self.upsertRemote(
                    decodeRemote(Lead.self, mutation) ?? fallbackLeads[mutation.entityID],
                    in: &leads
                )
            case .estimate:
                Self.upsertRemote(
                    decodeRemote(EstimateRecord.self, mutation) ?? fallbackEstimates[mutation.entityID],
                    in: &estimates
                )
            case .job:
                Self.upsertRemote(
                    decodeRemote(JobRecord.self, mutation) ?? fallbackJobs[mutation.entityID],
                    in: &jobs
                )
            case .invoice:
                Self.upsertRemote(
                    decodeRemote(InvoiceRecord.self, mutation) ?? fallbackInvoices[mutation.entityID],
                    in: &invoices
                )
            case .employee:
                Self.upsertRemote(
                    decodeRemote(EmployeeRecord.self, mutation) ?? fallbackEmployees[mutation.entityID],
                    in: &employees
                )
            case .catalog:
                Self.upsertRemote(
                    decodeRemote(ServiceCatalogItem.self, mutation) ?? fallbackCatalog[mutation.entityID],
                    in: &serviceCatalogItems
                )
            case .recurringWork:
                Self.upsertRemote(
                    decodeRemote(RecurringWorkTemplate.self, mutation) ?? fallbackRecurring[mutation.entityID],
                    in: &recurringWorkTemplates
                )
            case .assignment:
                if let assignment = decodeRemote(Assignment.self, mutation) ??
                    fallbackAssignments[mutation.entityID] {
                    canonicalAssignments.append(assignment)
                }
            case .custom:
                guard mutation.entityID == Self.businessProfileSynchronizationID else { break }
                businessProfile = decodeRemote(BusinessProfile.self, mutation) ??
                    fallbackBusinessProfile
            case .payment, .route:
                break
            }
            if let revision = operation.metadata["remoteRevision"] {
                synchronizedRecordRevisions[
                    synchronizationKey(
                        type: mutation.entityType,
                        id: mutation.entityID
                    )
                ] = revision
            }
        }

        // Historical server authority can contain more than one record with
        // the same human-facing assignment number. AssignmentStore correctly
        // rejects that invalid snapshot, but recovery must not turn one
        // duplicate into an empty assignment database. Keep the newest
        // authoritative record for each number and install every unaffected
        // assignment in one validated pass.
        let recoverableAssignments = Self.recoverableCanonicalAssignments(
            canonicalAssignments
        )
        try? assignmentStore.replaceAll(with: recoverableAssignments)

        saveSynchronizedRecordRevisions()
        persistAppliedSnapshotWithoutEnqueuingChanges()
    }

    private static func recoverableCanonicalAssignments(
        _ assignments: [Assignment]
    ) -> [Assignment] {
        var newestByNumber: [String: Assignment] = [:]
        for assignment in assignments {
            let key = assignment.assignmentNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let existing = newestByNumber[key] else {
                newestByNumber[key] = assignment
                continue
            }
            if assignment.updatedDate > existing.updatedDate ||
                (assignment.updatedDate == existing.updatedDate &&
                    assignment.id.uuidString < existing.id.uuidString) {
                newestByNumber[key] = assignment
            }
        }
        return Array(newestByNumber.values)
    }

    /// Reconciles durable device intent against authoritative changes pulled
    /// before upload. Identical intent is completed locally. Device changes
    /// older than the eight-hour stale window are superseded by the cloud;
    /// recent divergent intent remains queued for normal policy/conflict review.
    func reconcilePendingOperationsBeforeUpload(
        with remoteOperations: [PendingOfflineOperation],
        staleWindow: TimeInterval = 8 * 60 * 60
    ) -> (alreadyReflected: Int, superseded: Int) {
        var alreadyReflected = 0
        var superseded = 0

        for remote in remoteOperations where remote.type == .recordMutation {
            guard let entityID = remote.entityID,
                  let remoteMutation = try? OfflineRecordMutationCodec.decode(
                    remote.payload,
                    decoder: Self.recordSynchronizationDecoder
                  ) else { continue }
            let remoteRevision = remote.metadata["remoteRevision"]
            let candidates = offlineOperationQueue.operations.filter {
                $0.type == .recordMutation &&
                $0.entityType == remote.entityType &&
                $0.entityID == entityID &&
                !$0.status.isTerminal
            }

            for candidate in candidates {
                guard let localMutation = try? OfflineRecordMutationCodec.decode(
                    candidate.payload,
                    decoder: Self.recordSynchronizationDecoder
                ) else { continue }
                let isIdentical = localMutation.recordData == remoteMutation.recordData
                let isStale = candidate.createdAt.addingTimeInterval(staleWindow)
                    <= remote.updatedAt
                guard isIdentical || isStale else { continue }

                try? offlineOperationQueue.mutate(id: candidate.id) { operation in
                    operation.status = .synchronized
                    operation.synchronizedAt = Date()
                    operation.failure = nil
                    operation.conflict = nil
                    operation.nextRetryAt = nil
                    if let remoteRevision {
                        operation.metadata["remoteRevision"] = remoteRevision
                    }
                    if isIdentical {
                        operation.metadata["recoveryClassification"] =
                            "alreadyReflected"
                    } else {
                        operation.metadata["recoveryClassification"] =
                            "supersededByCloud"
                        operation.metadata["staleDeviceChangeDiscarded"] = "true"
                    }
                }
                if isIdentical { alreadyReflected += 1 }
                else { superseded += 1 }
            }
        }
        return (alreadyReflected, superseded)
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

    private func applyRemoteRecordMutation(
        _ mutation: OfflineRecordMutationPayload,
        materializeRecurringWork: Bool = true
    ) {
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
            if materializeRecurringWork {
                materializeRecurringWorkHorizon()
            }
        case .custom:
            guard mutation.entityID == Self.businessProfileSynchronizationID,
                  let profile = decodeRemote(BusinessProfile.self, mutation) else {
                return
            }
            businessProfile = profile
            applyCompanyStandardTaxToUncalculatedDraftInvoices()
        case .payment, .route:
            break
        }
    }

    func enqueueBusinessProfileSynchronization() {
        guard offlineSynchronizationMode.requiresRemoteQueue,
              canManageCompany else { return }
        enqueueRecordMutation(
            entityType: .custom,
            entityID: Self.businessProfileSynchronizationID,
            value: businessProfile
        )
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
        baseRecordData: Data? = nil,
        modifiedAt: Date = Date()
    ) {
        guard offlineSynchronizationMode.requiresRemoteQueue else { return }
        do {
            let recordData = try Self.recordSynchronizationEncoder.encode(value)
            let operationID = UUID()
            let baseRevision = synchronizedRecordRevisions[
                synchronizationKey(type: entityType, id: entityID)
            ]
            let classification = SynchronizationMutationClassifier.classify(
                entityType: entityType,
                baseRecordData: baseRecordData,
                recordData: recordData
            )
            let payload = try OfflineRecordMutationCodec.envelopePayload(
                operationID: operationID,
                entityType: entityType,
                entityID: entityID,
                recordData: recordData,
                baseRecordData: baseRecordData,
                modifiedAt: modifiedAt,
                baseRevision: baseRevision,
                mutationKind: classification.kind,
                changedFields: classification.changedFields,
                commandName: classification.commandName,
                encoder: Self.recordSynchronizationEncoder
            )
            let operation = PendingOfflineOperation(
                id: operationID,
                type: .recordMutation,
                entityType: entityType,
                entityID: entityID,
                actionName: "upsertRecord",
                actorEmployeeID: nil,
                payload: payload,
                createdAt: modifiedAt,
                baseRevision: baseRevision,
                metadata: [
                    "recordSync": "true",
                    "mutationEnvelopeVersion": String(
                        SynchronizationMutationEnvelope.currentSchemaVersion
                    ),
                    "mutationKind": classification.kind.rawValue,
                    "changedFields": classification.changedFields.joined(separator: ","),
                    "commandName": classification.commandName ?? "",
                ]
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
