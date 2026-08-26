//
//  OfflineConflictResolver.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 5 – Safe merge and audited conflict resolution.
//

import Foundation

enum OfflineConflictEvaluation: Equatable {
    case automaticallyMerged(OfflineConflictInformation)
    case requiresHumanReview(OfflineConflictInformation, conflictingPaths: [String])
}

enum OfflineConflictResolutionError: LocalizedError, Equatable {
    case operationNotFound
    case noUnresolvedConflict
    case remoteVersionUnavailable
    case invalidResolution
    case unableToMergePayload

    var errorDescription: String? {
        switch self {
        case .operationNotFound:
            return "The queued operation could not be found."
        case .noUnresolvedConflict:
            return "This operation does not have an unresolved conflict."
        case .remoteVersionUnavailable:
            return "The remote version is unavailable."
        case .invalidResolution:
            return "Select Keep Local, Keep Remote, or Preserve Both."
        case .unableToMergePayload:
            return "The conflicting payloads could not be merged safely."
        }
    }
}

/// Performs conservative three-way JSON merges. Values changed on only one
/// side are retained. Different changes to the same path always require a
/// human decision, ensuring technician data is never silently discarded.
struct OfflineConflictResolver {
    func evaluate(
        _ conflict: OfflineConflictInformation,
        at timestamp: Date = Date()
    ) -> OfflineConflictEvaluation {
        guard conflict.kind == .concurrentModification,
              let base = conflict.baseVersion,
              let remote = conflict.remoteVersion,
              let mergedPayload = merge(
                base: base.payload,
                local: conflict.localVersion.payload,
                remote: remote.payload
              ) else {
            return .requiresHumanReview(conflict, conflictingPaths: ["record"])
        }

        switch mergedPayload {
        case let .merged(payload):
            var resolved = conflict
            resolved.resolution = .automaticallyMerged
            resolved.resolvedAt = timestamp
            resolved.resolutionNote = "PFSS merged independent local and remote changes automatically."
            resolved.mergedVersion = OfflineRecordVersion(
                revision: remote.revision,
                modifiedAt: timestamp,
                source: .merged,
                payload: payload
            )
            return .automaticallyMerged(resolved)
        case let .conflict(paths):
            return .requiresHumanReview(conflict, conflictingPaths: paths)
        }
    }

    private enum MergeResult {
        case merged(OfflineOperationPayload)
        case conflict([String])
    }

    private func merge(
        base: OfflineOperationPayload,
        local: OfflineOperationPayload,
        remote: OfflineOperationPayload
    ) -> MergeResult? {
        guard base.schemaVersion == local.schemaVersion,
              base.schemaVersion == remote.schemaVersion,
              base.contentType == local.contentType,
              base.contentType == remote.contentType,
              let baseObject = try? JSONSerialization.jsonObject(with: base.body),
              let localObject = try? JSONSerialization.jsonObject(with: local.body),
              let remoteObject = try? JSONSerialization.jsonObject(with: remote.body) else {
            return nil
        }

        var conflicts: [String] = []
        let merged = mergeValue(
            base: baseObject,
            local: localObject,
            remote: remoteObject,
            path: "",
            conflicts: &conflicts
        )
        guard conflicts.isEmpty,
              JSONSerialization.isValidJSONObject(merged),
              let body = try? JSONSerialization.data(
                withJSONObject: merged,
                options: [.sortedKeys]
              ) else {
            return .conflict(conflicts.isEmpty ? ["record"] : conflicts.sorted())
        }

        return .merged(
            OfflineOperationPayload(
                schemaVersion: local.schemaVersion,
                contentType: local.contentType,
                body: body
            )
        )
    }

    private func mergeValue(
        base: Any,
        local: Any,
        remote: Any,
        path: String,
        conflicts: inout [String]
    ) -> Any {
        if valuesEqual(local, remote) { return local }
        if valuesEqual(local, base) { return remote }
        if valuesEqual(remote, base) { return local }

        if let baseDictionary = base as? [String: Any],
           let localDictionary = local as? [String: Any],
           let remoteDictionary = remote as? [String: Any] {
            var merged: [String: Any] = [:]
            let keys = Set(baseDictionary.keys)
                .union(localDictionary.keys)
                .union(remoteDictionary.keys)

            for key in keys {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                let baseValue = baseDictionary[key] ?? MissingValue.shared
                let localValue = localDictionary[key] ?? MissingValue.shared
                let remoteValue = remoteDictionary[key] ?? MissingValue.shared
                let value = mergeValue(
                    base: baseValue,
                    local: localValue,
                    remote: remoteValue,
                    path: childPath,
                    conflicts: &conflicts
                )
                if !(value is MissingValue) {
                    merged[key] = value
                }
            }
            return merged
        }

        conflicts.append(path.isEmpty ? "record" : path)
        return local
    }

    private func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if lhs is MissingValue || rhs is MissingValue {
            return lhs is MissingValue && rhs is MissingValue
        }
        return (lhs as AnyObject).isEqual(rhs)
    }

    private final class MissingValue {
        static let shared = MissingValue()
        private init() {}
    }
}

/// Owns explicit human resolutions and writes the decision into the durable
/// conflict envelope before allowing queue processing to continue.
@MainActor
final class OfflineConflictResolutionService {
    private let queue: OfflineOperationQueue

    private static let recordMutationEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let recordMutationDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(queue: OfflineOperationQueue) {
        self.queue = queue
    }

    func resolve(
        operationID: UUID,
        resolution: OfflineConflictResolution,
        employeeID: UUID?,
        note: String,
        at timestamp: Date = Date(),
        resubmitLocal: Bool = true
    ) throws {
        guard var operation = queue.operation(id: operationID) else {
            throw OfflineConflictResolutionError.operationNotFound
        }
        guard var conflict = operation.conflict,
              conflict.requiresHumanReview else {
            throw OfflineConflictResolutionError.noUnresolvedConflict
        }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        conflict.resolution = resolution
        conflict.resolvedAt = timestamp
        conflict.resolvedByEmployeeID = employeeID
        conflict.resolutionNote = cleanNote.isEmpty
            ? "Conflict resolved by an authorized PFSS user."
            : cleanNote

        switch resolution {
        case .keptLocal:
            operation.payload = conflict.localVersion.payload
            do {
                try OfflineRecordMutationCodec.rebase(
                    &operation,
                    to: conflict.remoteVersion?.revision,
                    decoder: Self.recordMutationDecoder,
                    encoder: Self.recordMutationEncoder
                )
            } catch {
                throw OfflineConflictResolutionError.unableToMergePayload
            }
            operation.status = resubmitLocal ? .pending : .synchronized
            operation.synchronizedAt = resubmitLocal ? nil : timestamp
            operation.failure = nil
            operation.nextRetryAt = nil
        case .keptRemote:
            guard let remote = conflict.remoteVersion else {
                throw OfflineConflictResolutionError.remoteVersionUnavailable
            }
            operation.payload = remote.payload
            operation.status = .synchronized
            operation.synchronizedAt = timestamp
            operation.failure = nil
            operation.nextRetryAt = nil
        case .preservedBoth:
            operation.status = .cancelled
            operation.failure = nil
            operation.nextRetryAt = nil
        case .unresolved, .automaticallyMerged:
            throw OfflineConflictResolutionError.invalidResolution
        }

        operation.conflict = conflict
        operation.updatedAt = timestamp
        operation.metadata["conflictResolution"] = resolution.rawValue
        operation.metadata["conflictResolvedAt"] = ISO8601DateFormatter().string(from: timestamp)
        if let employeeID {
            operation.metadata["conflictResolvedBy"] = employeeID.uuidString
        }
        try queue.update(operation)
    }
}
