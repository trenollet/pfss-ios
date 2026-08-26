//
//  PFSSSynchronizationDiagnostics.swift
//  PPS Receipt Printer
//
//  Phase 20 Step 7 – privacy-limited support diagnostics.
//

import Foundation
import UIKit

struct PFSSSynchronizationDiagnosticSubmission: Decodable, Equatable {
    var caseCode: String
    var submittedAt: Date
    var expiresAt: Date
}

struct PFSSSynchronizationDiagnosticBundle: Encodable {
    struct App: Encodable {
        var version: String
        var build: String
    }

    struct Device: Encodable {
        var model: String
        var systemName: String
        var systemVersion: String
    }

    struct Synchronization: Encodable {
        var cursor: Int
        var connectivity: String
        var cloudAccessStatus: String
        var queuePersistenceError: String?
        var latestRecovery: SynchronizationRecoverySummary?
    }

    /// Privacy-safe local inventory used to detect incomplete recovery without
    /// uploading customer, employee, job, or service contents.
    struct Inventory: Encodable {
        var customers: Int
        var sites: Int
        var leads: Int
        var estimates: Int
        var jobs: Int
        var invoices: Int
        var employees: Int
        var catalogItems: Int
        var recurringWorkTemplates: Int
        var assignments: Int
    }

    struct Failure: Encodable {
        var category: String
        var code: String?
        var isRetryable: Bool
        var occurredAt: Date
    }

    struct Conflict: Encodable {
        var kind: String
        var detectedAt: Date
        var resolution: String
    }

    struct Retry: Encodable {
        var attemptNumber: Int
        var startedAt: Date
        var completedAt: Date?
        var outcome: String?
        var failureCode: String?
    }

    struct Operation: Encodable {
        var operationID: String
        var idempotencyKey: String
        var sequenceNumber: UInt64
        var entityType: String
        var recordID: String?
        var actionName: String
        var status: String
        var createdAt: Date
        var updatedAt: Date
        var nextRetryAt: Date?
        var failure: Failure?
        var conflict: Conflict?
        var metadata: [String: String]
        var retries: [Retry]
    }

    var schemaVersion = 1
    var generatedAt: Date
    var description: String?
    var app: App
    var device: Device
    var synchronization: Synchronization
    var inventory: Inventory
    var operations: [Operation]
}

@MainActor
enum PFSSSynchronizationDiagnosticCollector {
    private static let allowedMetadata = Set([
        "serverQuarantineID", "serverQuarantineStatus", "serverConflictID",
        "sourceOperationID", "mutationEnvelopeVersion", "mutationKind",
        "commandName", "changedFields", "quarantineDeliveryStatus",
        "conflictDeliveryStatus", "appliedQuarantineResolutionID",
        "quarantineResolution", "recoveryClassification", "remoteRevision",
    ])

    static func make(
        store: AppDataStore,
        session: PFSSCloudflareSession,
        description: String?
    ) -> PFSSSynchronizationDiagnosticBundle {
        let bundle = Bundle.main
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        let cursorKey = PFSSCloudSynchronizationStateKeys.cursor(
            deviceID: session.device.id
        )
        let operations = store.offlineOperationQueue.orderedOperations
            .filter { !$0.status.isTerminal || $0.status == .synchronized }
            .suffix(100)
            .map(operation)
        return PFSSSynchronizationDiagnosticBundle(
            generatedAt: Date(),
            description: description?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).nilIfEmpty,
            app: .init(version: version, build: build),
            device: .init(
                model: UIDevice.current.model,
                systemName: UIDevice.current.systemName,
                systemVersion: UIDevice.current.systemVersion
            ),
            synchronization: .init(
                cursor: UserDefaults.standard.integer(forKey: cursorKey),
                connectivity: store.offlineConnectivityMonitor.status.rawValue,
                cloudAccessStatus: accessDescription(
                    store.cloudSynchronizationAccessStatus
                ),
                queuePersistenceError: store.offlineOperationQueue
                    .lastPersistenceError?.localizedDescription,
                latestRecovery: PFSSSynchronizationRecoveryStatus.shared.latest
            ),
            inventory: .init(
                customers: store.customers.count,
                sites: store.sites.count,
                leads: store.leads.count,
                estimates: store.estimates.count,
                jobs: store.jobs.count,
                invoices: store.invoices.count,
                employees: store.employees.count,
                catalogItems: store.serviceCatalogItems.count,
                recurringWorkTemplates: store.recurringWorkTemplates.count,
                assignments: store.assignmentStore.assignments.count
            ),
            operations: operations
        )
    }

    private static func operation(
        _ operation: PendingOfflineOperation
    ) -> PFSSSynchronizationDiagnosticBundle.Operation {
        let metadata = operation.metadata.filter {
            allowedMetadata.contains($0.key)
        }
        return .init(
            operationID: operation.id.uuidString.lowercased(),
            idempotencyKey: operation.idempotencyKey,
            sequenceNumber: operation.sequenceNumber,
            entityType: operation.entityType.rawValue,
            recordID: operation.entityID?.uuidString.lowercased(),
            actionName: operation.actionName,
            status: operation.status.rawValue,
            createdAt: operation.createdAt,
            updatedAt: operation.updatedAt,
            nextRetryAt: operation.nextRetryAt,
            failure: operation.failure.map {
                .init(
                    category: $0.category.rawValue,
                    code: $0.code,
                    isRetryable: $0.isRetryable,
                    occurredAt: $0.occurredAt
                )
            },
            conflict: operation.conflict.map {
                .init(
                    kind: $0.kind.rawValue,
                    detectedAt: $0.detectedAt,
                    resolution: $0.resolution.rawValue
                )
            },
            metadata: metadata,
            retries: operation.retryAttempts.suffix(10).map {
                .init(
                    attemptNumber: $0.attemptNumber,
                    startedAt: $0.startedAt,
                    completedAt: $0.completedAt,
                    outcome: $0.outcome?.rawValue,
                    failureCode: $0.failure?.code
                )
            }
        )
    }

    private static func accessDescription(
        _ status: PFSSCloudSynchronizationAccessStatus
    ) -> String {
        switch status {
        case .checking: "checking"
        case .available: "available"
        case .suspended: "suspended"
        case .accountHold: "accountHold"
        case .unavailable: "unavailable"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
