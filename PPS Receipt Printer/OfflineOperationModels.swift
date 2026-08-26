//
//  OfflineOperationModels.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 1 – Shared offline operation model.
//

import Foundation

/// The business operation that must eventually cross a synchronization
/// boundary. These values describe intent rather than a specific cloud API.
enum OfflineOperationType: String, CaseIterable, Codable, Hashable {
    case workflowAction
    case jobNote
    case jobTimestamp
    case invoiceHandoff
    case paymentRecording
    case routeChange
    case recordMutation
}

/// The PFSS record family affected by an offline operation.
enum OfflineEntityType: String, CaseIterable, Codable, Hashable {
    case job
    case assignment
    case invoice
    case payment
    case route
    case customer
    case site
    case lead
    case estimate
    case employee
    case catalog
    case recurringWork
    case custom
}

/// Durable queue state. A synchronization adapter may only attempt operations
/// whose state permits another attempt.
enum OfflineOperationStatus: String, CaseIterable, Codable, Hashable {
    case pending
    case synchronizing
    case waitingForRetry
    case failed
    case conflicted
    case synchronized
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .synchronized, .cancelled:
            return true
        case .pending, .synchronizing, .waitingForRetry, .failed, .conflicted:
            return false
        }
    }

    var requiresHumanAttention: Bool {
        self == .failed || self == .conflicted
    }
}

/// Versioned, type-labelled bytes keep the queue independent of a future
/// CloudKit or server transport while still allowing strongly typed payloads.
struct OfflineOperationPayload: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var contentType: String
    var body: Data

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        contentType: String,
        body: Data
    ) {
        self.schemaVersion = schemaVersion
        self.contentType = contentType
        self.body = body
    }

    init<Value: Encodable>(
        _ value: Value,
        contentType: String = String(reflecting: Value.self),
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        self.init(
            contentType: contentType,
            body: try encoder.encode(value)
        )
    }

    func decode<Value: Decodable>(
        _ type: Value.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(type, from: body)
    }
}

enum OfflineFailureCategory: String, CaseIterable, Codable, Hashable {
    case connectivity
    case timeout
    case authentication
    case authorization
    case validation
    case server
    case decoding
    case conflict
    case unknown
}

struct SynchronizationIssueExplanation: Equatable {
    var title: String
    var summary: String
    var impact: String
    var recommendedAction: String
    var technicalCode: String?

    static func explain(
        failure: OfflineFailureDetails?,
        entityType: OfflineEntityType
    ) -> SynchronizationIssueExplanation {
        let rawCode = failure?.code?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        switch rawCode {
        case "technician_assignment_change_requires_manager":
            return .init(
                title: "A Manager Must Approve This Assignment Change",
                summary: "An employee tried to change who is assigned to this work. Only a Manager or Owner can approve or correct that crew change.",
                impact: "The current company assignment remains unchanged until an authorized person reviews it.",
                recommendedAction: "Review the intended crew, correct it if needed, then approve the repaired assignment or discard the employee change.",
                technicalCode: rawCode
            )
        case "employee_role_change_requires_manager":
            return .init(
                title: "A Manager Must Approve This Employee Access Change",
                summary: "An employee device attempted to change a team member's role or permissions.",
                impact: "The existing employee access remains in effect.",
                recommendedAction: "Confirm the correct employee role before approving or discarding the change.",
                technicalCode: rawCode
            )
        case "catalog_change_requires_manager":
            return .init(
                title: "A Manager Must Approve This Service Change",
                summary: "An employee device attempted to change shared service or pricing information.",
                impact: "The current company service record remains unchanged.",
                recommendedAction: "Review the service details and approve a corrected Manager change or discard the employee change.",
                technicalCode: rawCode
            )
        case "mutation_rebase_failed":
            return .init(
                title: "This Device Change Needs Repair",
                summary: "PFSS could not safely place this saved device change on top of the newer company record.",
                impact: "The device change is preserved, but it has not changed the company record.",
                recommendedAction: "Compare the intended and current values, correct the record, and submit a repaired replacement.",
                technicalCode: rawCode
            )
        default:
            let recordName = entityType.conflictDisplayName.lowercased()
            return .init(
                title: "This \(entityType.conflictDisplayName) Change Needs Review",
                summary: "PFSS could not safely synchronize this \(recordName) change. The employee's work is preserved for review.",
                impact: "The accepted company record remains unchanged unless an authorized repair is approved.",
                recommendedAction: "Compare the device change with the current company record, then repair, retry, or discard it.",
                technicalCode: rawCode
            )
        }
    }
}

/// A durable explanation of the latest synchronization failure. User-facing
/// UI should display `message`; deeper details remain available for support.
struct OfflineFailureDetails: Codable, Hashable {
    var category: OfflineFailureCategory
    var code: String?
    var message: String
    var isRetryable: Bool
    var occurredAt: Date
    var underlyingDescription: String?
    var metadata: [String: String]

    init(
        category: OfflineFailureCategory,
        code: String? = nil,
        message: String,
        isRetryable: Bool,
        occurredAt: Date = Date(),
        underlyingDescription: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.category = category
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
        self.occurredAt = occurredAt
        self.underlyingDescription = underlyingDescription
        self.metadata = metadata
    }
}

enum OfflineRetryOutcome: String, CaseIterable, Codable, Hashable {
    case succeeded
    case failed
    case deferred
    case cancelled
}

/// An immutable record of one processor attempt. Keeping the complete history
/// makes retry behavior auditable instead of storing only a counter.
struct OfflineRetryAttempt: Identifiable, Codable, Hashable {
    var id: UUID
    var attemptNumber: Int
    var startedAt: Date
    var completedAt: Date?
    var outcome: OfflineRetryOutcome?
    var scheduledDelaySeconds: TimeInterval?
    var failure: OfflineFailureDetails?

    init(
        id: UUID = UUID(),
        attemptNumber: Int,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        outcome: OfflineRetryOutcome? = nil,
        scheduledDelaySeconds: TimeInterval? = nil,
        failure: OfflineFailureDetails? = nil
    ) {
        self.id = id
        self.attemptNumber = attemptNumber
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.outcome = outcome
        self.scheduledDelaySeconds = scheduledDelaySeconds
        self.failure = failure
    }
}

enum OfflineRecordVersionSource: String, CaseIterable, Codable, Hashable {
    case local
    case remote
    case merged
}

/// A complete version involved in a conflict. Both local and remote payloads
/// are preserved until PFSS can merge them or a human selects a resolution.
struct OfflineRecordVersion: Codable, Hashable {
    var revision: String?
    var modifiedAt: Date
    var source: OfflineRecordVersionSource
    var payload: OfflineOperationPayload

    init(
        revision: String? = nil,
        modifiedAt: Date,
        source: OfflineRecordVersionSource,
        payload: OfflineOperationPayload
    ) {
        self.revision = revision
        self.modifiedAt = modifiedAt
        self.source = source
        self.payload = payload
    }
}

enum OfflineConflictKind: String, CaseIterable, Codable, Hashable {
    case concurrentModification
    case remoteDeletion
    case duplicateCreation
    case incompatibleSchema
    case unknown
}

enum OfflineConflictResolution: String, CaseIterable, Codable, Hashable {
    case unresolved
    case automaticallyMerged
    case keptLocal
    case keptRemote
    case preservedBoth
}

struct OfflineConflictInformation: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: OfflineConflictKind
    var detectedAt: Date
    var localVersion: OfflineRecordVersion
    /// Last mutually observed version used for safe three-way merging.
    /// Older persisted conflicts decode this as `nil` and require review.
    var baseVersion: OfflineRecordVersion?
    var remoteVersion: OfflineRecordVersion?
    var resolution: OfflineConflictResolution
    var resolvedAt: Date?
    var resolvedByEmployeeID: UUID?
    var resolutionNote: String?
    var mergedVersion: OfflineRecordVersion?

    init(
        id: UUID = UUID(),
        kind: OfflineConflictKind,
        detectedAt: Date = Date(),
        localVersion: OfflineRecordVersion,
        baseVersion: OfflineRecordVersion? = nil,
        remoteVersion: OfflineRecordVersion? = nil,
        resolution: OfflineConflictResolution = .unresolved,
        resolvedAt: Date? = nil,
        resolvedByEmployeeID: UUID? = nil,
        resolutionNote: String? = nil,
        mergedVersion: OfflineRecordVersion? = nil
    ) {
        self.id = id
        self.kind = kind
        self.detectedAt = detectedAt
        self.localVersion = localVersion
        self.baseVersion = baseVersion
        self.remoteVersion = remoteVersion
        self.resolution = resolution
        self.resolvedAt = resolvedAt
        self.resolvedByEmployeeID = resolvedByEmployeeID
        self.resolutionNote = resolutionNote
        self.mergedVersion = mergedVersion
    }

    var requiresHumanReview: Bool {
        resolution == .unresolved
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case detectedAt
        case localVersion
        case baseVersion
        case remoteVersion
        case resolution
        case resolvedAt
        case resolvedByEmployeeID
        case resolutionNote
        case mergedVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(OfflineConflictKind.self, forKey: .kind)
        detectedAt = try container.decode(Date.self, forKey: .detectedAt)
        localVersion = try container.decode(OfflineRecordVersion.self, forKey: .localVersion)
        baseVersion = try container.decodeIfPresent(OfflineRecordVersion.self, forKey: .baseVersion)
        remoteVersion = try container.decodeIfPresent(OfflineRecordVersion.self, forKey: .remoteVersion)
        resolution = try container.decode(OfflineConflictResolution.self, forKey: .resolution)
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        resolvedByEmployeeID = try container.decodeIfPresent(UUID.self, forKey: .resolvedByEmployeeID)
        resolutionNote = try container.decodeIfPresent(String.self, forKey: .resolutionNote)
        mergedVersion = try container.decodeIfPresent(OfflineRecordVersion.self, forKey: .mergedVersion)
    }
}

/// The standard durable envelope for every action waiting to synchronize.
///
/// `idempotencyKey` must be sent unchanged on every retry. A future remote
/// adapter uses it to recognize an operation it has already accepted and avoid
/// performing technician actions twice.
struct PendingOfflineOperation: Identifiable, Codable, Hashable {
    var id: UUID
    var idempotencyKey: String
    /// Monotonic queue position assigned by `OfflineOperationQueue`.
    var sequenceNumber: UInt64
    var type: OfflineOperationType
    var entityType: OfflineEntityType
    var entityID: UUID?
    var actionName: String
    var actorEmployeeID: UUID?
    var payload: OfflineOperationPayload
    var status: OfflineOperationStatus

    var createdAt: Date
    var updatedAt: Date
    var firstAttemptAt: Date?
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    var synchronizedAt: Date?

    var retryAttempts: [OfflineRetryAttempt]
    var failure: OfflineFailureDetails?
    var conflict: OfflineConflictInformation?

    /// Revision observed before the local operation was created. A remote
    /// adapter can use this for optimistic conflict detection.
    var baseRevision: String?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        idempotencyKey: String? = nil,
        sequenceNumber: UInt64 = 0,
        type: OfflineOperationType,
        entityType: OfflineEntityType,
        entityID: UUID? = nil,
        actionName: String,
        actorEmployeeID: UUID? = nil,
        payload: OfflineOperationPayload,
        status: OfflineOperationStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        firstAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        nextRetryAt: Date? = nil,
        synchronizedAt: Date? = nil,
        retryAttempts: [OfflineRetryAttempt] = [],
        failure: OfflineFailureDetails? = nil,
        conflict: OfflineConflictInformation? = nil,
        baseRevision: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
            ?? "pfss-operation-\(id.uuidString.lowercased())"
        self.sequenceNumber = sequenceNumber
        self.type = type
        self.entityType = entityType
        self.entityID = entityID
        self.actionName = actionName
        self.actorEmployeeID = actorEmployeeID
        self.payload = payload
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.firstAttemptAt = firstAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = nextRetryAt
        self.synchronizedAt = synchronizedAt
        self.retryAttempts = retryAttempts
        self.failure = failure
        self.conflict = conflict
        self.baseRevision = baseRevision
        self.metadata = metadata
    }

    var attemptCount: Int {
        retryAttempts.count
    }

    var isReadyToSynchronize: Bool {
        isReadyToSynchronize(at: Date())
    }

    func isReadyToSynchronize(at date: Date) -> Bool {
        guard !status.isTerminal,
              status != .synchronizing,
              status != .conflicted else {
            return false
        }

        guard failure?.isRetryable != false else { return false }

        return nextRetryAt.map { $0 <= date } ?? true
    }

    /// Queue dependencies are intentionally narrower than queue order. Every
    /// operation for the same record is serialized, while unrelated records
    /// remain free to synchronize. Domain commands may add an aggregate key
    /// or explicit prerequisite operation identifiers through metadata.
    var synchronizationDependencyKeys: Set<String> {
        var keys: Set<String> = []
        if let entityID {
            keys.insert("record:\(entityType.rawValue):\(entityID.uuidString.lowercased())")
        } else {
            // Identity-free legacy operations must not globally block each
            // other. Their own durable operation identity is the safe fallback.
            keys.insert("operation:\(id.uuidString.lowercased())")
        }

        for metadataKey in ["dependencyKey", "dependencyKeys", "aggregateDependencyKey"] {
            guard let value = metadata[metadataKey] else { continue }
            value.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .forEach { keys.insert("explicit:\($0)") }
        }
        return keys
    }

    var prerequisiteOperationIDs: Set<UUID> {
        guard let value = metadata["prerequisiteOperationIDs"] else { return [] }
        return Set(value.split(separator: ",").compactMap {
            UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }
}
