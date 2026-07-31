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
}
