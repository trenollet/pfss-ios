//
//  SynchronizationMutationEnvelope.swift
//  PPS Receipt Printer
//
//  Phase 20 Step 2 – Versioned, backward-compatible mutation envelope.
//

import Foundation

enum SynchronizationMutationKind: String, Codable, Hashable {
    case wholeRecord
    case fieldPatch
    case appendFact
    case domainCommand
}

struct SynchronizationMutationClassification: Hashable {
    let kind: SynchronizationMutationKind
    let changedFields: [String]
    let commandName: String?
}

enum SynchronizationMutationClassifier {
    static func classify(
        entityType: OfflineEntityType,
        baseRecordData: Data?,
        recordData: Data
    ) -> SynchronizationMutationClassification {
        guard let baseRecordData,
              let base = jsonObject(baseRecordData),
              let current = jsonObject(recordData) else {
            return .init(kind: .wholeRecord, changedFields: [], commandName: nil)
        }
        let fields = Set(base.keys).union(current.keys).filter {
            canonicalData(base[$0]) != canonicalData(current[$0])
        }.sorted()
        guard !fields.isEmpty else {
            return .init(kind: .fieldPatch, changedFields: [], commandName: nil)
        }

        let changed = Set(fields)
        if let appendFields = appendOnlyFields[entityType],
           changed.isSubset(of: appendFields) {
            return .init(kind: .appendFact, changedFields: fields, commandName: nil)
        }
        if let command = commandName(entityType: entityType, changed: changed) {
            return .init(kind: .domainCommand, changedFields: fields, commandName: command)
        }
        return .init(kind: .fieldPatch, changedFields: fields, commandName: nil)
    }

    private static let appendOnlyFields: [OfflineEntityType: Set<String>] = [
        .job: ["timelineEvents"],
        .assignment: ["history"],
        .invoice: ["receipts"],
    ]

    private static func commandName(
        entityType: OfflineEntityType,
        changed: Set<String>
    ) -> String? {
        if changed.contains("lifecycleStatus") { return "record.lifecycle" }
        switch entityType {
        case .job:
            if !changed.isDisjoint(with: ["isRecurring", "recurrenceFrequency",
                "recurrenceEndMode", "recurrenceEndDate", "recurrenceOccurrenceCount",
                "recurrenceSeriesID", "recurrenceSequence", "recurringWorkTemplateID",
                "recurringWorkOccurrenceKey"]) { return "recurringWork.update" }
            if !changed.isDisjoint(with: ["primaryTechnicianID", "secondaryTechnicianID"]) {
                return "job.assign"
            }
            if !changed.isDisjoint(with: ["scheduledDate", "scheduledDurationOverrideMinutes",
                "assignmentSchedulingMode", "arrivalWindowEnd", "completionDeadline",
                "assignmentPriority"]) { return "job.reschedule" }
            if !changed.isDisjoint(with: ["status", "workflowState", "setupStartDate",
                "workStartDate", "completedDate"]) { return "job.transition" }
        case .assignment:
            if !changed.isDisjoint(with: ["dispatchNotes", "fieldNotes"]) {
                return "assignment.updateNotes"
            }
            if !changed.isDisjoint(with: ["crew"]) { return "assignment.assign" }
            if !changed.isDisjoint(with: ["scheduling", "priority", "routeSequence"]) {
                return "assignment.reschedule"
            }
            if !changed.isDisjoint(with: ["status", "dispatchedDate", "enRouteDate",
                "onSiteDate", "workCompletedDate", "invoiceReadyDate", "closedDate",
                "cancelledDate"]) { return "assignment.transition" }
        case .invoice:
            if !changed.isDisjoint(with: ["lineItems", "subtotal", "discount", "total",
                "taxSnapshot", "issueDate", "dueDate", "notes"]) {
                return "invoice.edit"
            }
            if !changed.isDisjoint(with: ["amountPaid", "balanceDue", "paidDate", "receipts"]) {
                return "invoice.recordPayment"
            }
            if changed.contains("status") { return "invoice.transition" }
        case .recurringWork:
            return "recurringWork.update"
        default:
            break
        }
        return nil
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return value as? [String: Any]
    }

    private static func canonicalData(_ value: Any?) -> Data? {
        guard let value else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }
}

/// JSON value used to retain fields introduced by newer envelope versions.
/// Older supported builds can decode, persist, and re-encode those fields
/// without understanding or silently deleting them.
indirect enum SynchronizationJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SynchronizationJSONValue])
    case array([SynchronizationJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: SynchronizationJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([SynchronizationJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported synchronization JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct SynchronizationMutationEnvelope: Codable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var operationID: UUID
    /// Informational client context only. The server derives authority from
    /// the authenticated request and must reject a nonmatching supplied value.
    var tenantID: String?
    var deviceID: String?
    var entityType: OfflineEntityType
    var recordID: UUID
    var baseRevision: String?
    var mutationKind: SynchronizationMutationKind
    var changedFields: [String]
    var commandName: String?
    /// The exact record body associated with `baseRevision`. This is retained
    /// so the server can prove which fields the device actually changed and
    /// perform a safe three-way merge. It is never treated as authoritative
    /// without matching the server's revision history.
    var baseRecordData: Data?
    var recordData: Data?
    var clientCreatedAt: Date
    var deviceModifiedAt: Date
    var actorEmployeeID: UUID?
    var unknownFields: [String: SynchronizationJSONValue]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        operationID: UUID,
        tenantID: String? = nil,
        deviceID: String? = nil,
        entityType: OfflineEntityType,
        recordID: UUID,
        baseRevision: String? = nil,
        mutationKind: SynchronizationMutationKind = .wholeRecord,
        changedFields: [String] = [],
        commandName: String? = nil,
        baseRecordData: Data? = nil,
        recordData: Data? = nil,
        clientCreatedAt: Date,
        deviceModifiedAt: Date,
        actorEmployeeID: UUID? = nil,
        unknownFields: [String: SynchronizationJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.tenantID = tenantID
        self.deviceID = deviceID
        self.entityType = entityType
        self.recordID = recordID
        self.baseRevision = baseRevision
        self.mutationKind = mutationKind
        self.changedFields = changedFields
        self.commandName = commandName
        self.baseRecordData = baseRecordData
        self.recordData = recordData
        self.clientCreatedAt = clientCreatedAt
        self.deviceModifiedAt = deviceModifiedAt
        self.actorEmployeeID = actorEmployeeID
        self.unknownFields = unknownFields
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static let knownKeys: Set<String> = [
        "schemaVersion", "operationID", "tenantID", "deviceID", "entityType",
        "recordID", "baseRevision", "mutationKind", "changedFields",
        "commandName", "baseRecordData", "recordData", "clientCreatedAt", "deviceModifiedAt",
        "actorEmployeeID",
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        func key(_ name: String) -> DynamicCodingKey {
            DynamicCodingKey(stringValue: name)!
        }
        schemaVersion = try container.decode(Int.self, forKey: key("schemaVersion"))
        operationID = try container.decode(UUID.self, forKey: key("operationID"))
        tenantID = try container.decodeIfPresent(String.self, forKey: key("tenantID"))
        deviceID = try container.decodeIfPresent(String.self, forKey: key("deviceID"))
        entityType = try container.decode(OfflineEntityType.self, forKey: key("entityType"))
        recordID = try container.decode(UUID.self, forKey: key("recordID"))
        baseRevision = try container.decodeIfPresent(String.self, forKey: key("baseRevision"))
        mutationKind = try container.decode(
            SynchronizationMutationKind.self,
            forKey: key("mutationKind")
        )
        changedFields = try container.decodeIfPresent(
            [String].self,
            forKey: key("changedFields")
        ) ?? []
        commandName = try container.decodeIfPresent(String.self, forKey: key("commandName"))
        baseRecordData = try container.decodeIfPresent(Data.self, forKey: key("baseRecordData"))
        recordData = try container.decodeIfPresent(Data.self, forKey: key("recordData"))
        clientCreatedAt = try container.decode(Date.self, forKey: key("clientCreatedAt"))
        deviceModifiedAt = try container.decode(Date.self, forKey: key("deviceModifiedAt"))
        actorEmployeeID = try container.decodeIfPresent(
            UUID.self,
            forKey: key("actorEmployeeID")
        )
        unknownFields = [:]
        for codingKey in container.allKeys where !Self.knownKeys.contains(codingKey.stringValue) {
            unknownFields[codingKey.stringValue] = try container.decode(
                SynchronizationJSONValue.self,
                forKey: codingKey
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        func key(_ name: String) -> DynamicCodingKey {
            DynamicCodingKey(stringValue: name)!
        }
        try container.encode(schemaVersion, forKey: key("schemaVersion"))
        try container.encode(operationID, forKey: key("operationID"))
        try container.encodeIfPresent(tenantID, forKey: key("tenantID"))
        try container.encodeIfPresent(deviceID, forKey: key("deviceID"))
        try container.encode(entityType, forKey: key("entityType"))
        try container.encode(recordID, forKey: key("recordID"))
        try container.encodeIfPresent(baseRevision, forKey: key("baseRevision"))
        try container.encode(mutationKind, forKey: key("mutationKind"))
        try container.encode(changedFields, forKey: key("changedFields"))
        try container.encodeIfPresent(commandName, forKey: key("commandName"))
        try container.encodeIfPresent(baseRecordData, forKey: key("baseRecordData"))
        try container.encodeIfPresent(recordData, forKey: key("recordData"))
        try container.encode(clientCreatedAt, forKey: key("clientCreatedAt"))
        try container.encode(deviceModifiedAt, forKey: key("deviceModifiedAt"))
        try container.encodeIfPresent(actorEmployeeID, forKey: key("actorEmployeeID"))
        for (name, value) in unknownFields where !Self.knownKeys.contains(name) {
            try container.encode(value, forKey: key(name))
        }
    }
}

enum OfflineRecordMutationCodec {
    static func envelopePayload(
        operationID: UUID,
        entityType: OfflineEntityType,
        entityID: UUID,
        recordData: Data,
        baseRecordData: Data? = nil,
        modifiedAt: Date,
        baseRevision: String?,
        mutationKind: SynchronizationMutationKind = .wholeRecord,
        changedFields: [String] = [],
        commandName: String? = nil,
        actorEmployeeID: UUID? = nil,
        encoder: JSONEncoder
    ) throws -> OfflineOperationPayload {
        try OfflineOperationPayload(
            SynchronizationMutationEnvelope(
                operationID: operationID,
                entityType: entityType,
                recordID: entityID,
                baseRevision: baseRevision,
                mutationKind: mutationKind,
                changedFields: changedFields,
                commandName: commandName,
                baseRecordData: baseRecordData,
                recordData: recordData,
                clientCreatedAt: modifiedAt,
                deviceModifiedAt: modifiedAt,
                actorEmployeeID: actorEmployeeID
            ),
            encoder: encoder
        )
    }

    static func decode(
        _ payload: OfflineOperationPayload,
        decoder: JSONDecoder
    ) throws -> OfflineRecordMutationPayload {
        if let envelope = try? payload.decode(
            SynchronizationMutationEnvelope.self,
            decoder: decoder
        ), envelope.schemaVersion >= SynchronizationMutationEnvelope.currentSchemaVersion,
           let recordData = envelope.recordData {
            return OfflineRecordMutationPayload(
                entityType: envelope.entityType,
                entityID: envelope.recordID,
                recordData: recordData,
                modifiedAt: envelope.deviceModifiedAt
            )
        }
        return try payload.decode(
            OfflineRecordMutationPayload.self,
            decoder: decoder
        )
    }

    /// Keeps the outer operation revision and its versioned envelope in lock
    /// step when a queued mutation is causally rebased onto an earlier local
    /// mutation accepted by the server. Legacy payloads are returned unchanged.
    static func rebasingBaseRevision(
        _ payload: OfflineOperationPayload,
        to baseRevision: String?,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) throws -> OfflineOperationPayload {
        guard var envelope = try? payload.decode(
            SynchronizationMutationEnvelope.self,
            decoder: decoder
        ) else { return payload }
        envelope.baseRevision = baseRevision
        return try OfflineOperationPayload(
            envelope,
            contentType: payload.contentType,
            encoder: encoder
        )
    }

    /// A record mutation carries its causal revision twice: once on the queue
    /// operation and once inside the versioned mutation envelope. Always
    /// change both together so the server never receives a split-brain
    /// mutation after an automatic merge or explicit conflict resolution.
    static func rebase(
        _ operation: inout PendingOfflineOperation,
        to baseRevision: String?,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) throws {
        operation.payload = try rebasingBaseRevision(
            operation.payload,
            to: baseRevision,
            decoder: decoder,
            encoder: encoder
        )
        operation.baseRevision = baseRevision
    }
}
