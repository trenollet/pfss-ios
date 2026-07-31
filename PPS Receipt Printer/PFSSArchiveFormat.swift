//
//  PFSSArchiveFormat.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 1 – Provider-neutral portable data archive foundation.
//

import Foundation
import CryptoKit

enum PFSSArchiveConstants {
    static let fileExtension = "pfssarchive"
    static let mediaType = "application/vnd.pfss.archive+json"
    static let currentArchiveFormatVersion = 1
    static let currentDataSchemaVersion = 1
}

enum PFSSArchiveProtection: String, Codable, Hashable {
    /// Step 1 establishes portable integrity validation. Encryption is added
    /// at the protected backup boundary before an archive leaves the device.
    case none
}

struct PFSSArchiveRecordCounts: Codable, Hashable {
    var customers: Int
    var sites: Int
    var leads: Int
    var estimates: Int
    var jobs: Int
    var invoices: Int
    var catalogItems: Int
    var recommendationRules: Int
    var employees: Int
    var assignments: Int
    var pendingOperations: Int

    var total: Int {
        customers + sites + leads + estimates + jobs + invoices +
        catalogItems + recommendationRules + employees + assignments +
        pendingOperations
    }
}

struct PFSSArchiveManifest: Codable, Identifiable, Hashable {
    var id: UUID
    var archiveFormatVersion: Int
    var dataSchemaVersion: Int
    var createdAt: Date
    var appVersion: String
    var appBuild: String
    var businessName: String
    var mediaType: String
    var protection: PFSSArchiveProtection
    var payloadByteCount: Int
    var payloadSHA256: String
    var recordCounts: PFSSArchiveRecordCounts
}

struct PFSSArchivePayload: Codable {
    var appData: PFSSDataSnapshot
    var pendingOperations: [PendingOfflineOperation]

    var recordCounts: PFSSArchiveRecordCounts {
        PFSSArchiveRecordCounts(
            customers: appData.customers.count,
            sites: appData.sites.count,
            leads: appData.leads.count,
            estimates: appData.estimates.count,
            jobs: appData.jobs.count,
            invoices: appData.invoices.count,
            catalogItems: appData.serviceCatalogItems.count,
            recommendationRules: appData.recommendationRules.count,
            employees: appData.employees.count,
            assignments: appData.assignments.count,
            pendingOperations: pendingOperations.count
        )
    }
}

private struct PFSSArchiveEnvelope: Codable {
    var manifest: PFSSArchiveManifest
    var payload: Data
}

struct PFSSValidatedArchive {
    var manifest: PFSSArchiveManifest
    var payload: PFSSArchivePayload
}

protocol PFSSArchivePayloadMigrating {
    var sourceSchemaVersion: Int { get }
    var destinationSchemaVersion: Int { get }
    func migrate(_ payload: Data) throws -> Data
}

enum PFSSArchiveError: LocalizedError, Equatable {
    case unreadableArchive
    case unsupportedMediaType(String)
    case unsupportedArchiveFormat(found: Int, supported: Int)
    case newerDataSchema(found: Int, supported: Int)
    case missingMigration(from: Int)
    case invalidMigrationPath(from: Int, to: Int)
    case payloadSizeMismatch
    case checksumMismatch
    case unreadablePayload

    var errorDescription: String? {
        switch self {
        case .unreadableArchive:
            return "The selected file is not a readable PFSS archive."
        case .unsupportedMediaType:
            return "The selected file is not a supported PFSS archive type."
        case let .unsupportedArchiveFormat(found, supported):
            return "Archive format \(found) is not supported by format \(supported)."
        case let .newerDataSchema(found, supported):
            return "This backup uses data schema \(found). Update PFSS to a version that supports schema \(found); this version supports through \(supported)."
        case let .missingMigration(version):
            return "No safe migration is available for data schema \(version)."
        case let .invalidMigrationPath(source, destination):
            return "The archive migration path from schema \(source) to \(destination) is invalid."
        case .payloadSizeMismatch:
            return "The archive payload size does not match its manifest."
        case .checksumMismatch:
            return "The archive failed its integrity check and may be damaged or incomplete."
        case .unreadablePayload:
            return "The archive contents could not be decoded safely."
        }
    }
}

struct PFSSArchiveService {
    private let migrations: [Int: any PFSSArchivePayloadMigrating]
    private let appVersion: String
    private let appBuild: String

    init(
        migrations: [any PFSSArchivePayloadMigrating] = [],
        appVersion: String = PFSSBuildIdentity.version,
        appBuild: String = PFSSBuildIdentity.build
    ) {
        self.migrations = Dictionary(
            uniqueKeysWithValues: migrations.map { ($0.sourceSchemaVersion, $0) }
        )
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    func createArchive(
        payload: PFSSArchivePayload,
        businessName: String,
        createdAt: Date = Date()
    ) throws -> Data {
        let payloadData = try Self.encoder.encode(payload)
        let normalizedBusinessName = businessName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let manifest = PFSSArchiveManifest(
            id: UUID(),
            archiveFormatVersion: PFSSArchiveConstants.currentArchiveFormatVersion,
            dataSchemaVersion: PFSSArchiveConstants.currentDataSchemaVersion,
            createdAt: createdAt,
            appVersion: appVersion,
            appBuild: appBuild,
            businessName: normalizedBusinessName,
            mediaType: PFSSArchiveConstants.mediaType,
            protection: .none,
            payloadByteCount: payloadData.count,
            payloadSHA256: Self.sha256(payloadData),
            recordCounts: payload.recordCounts
        )
        return try Self.encoder.encode(
            PFSSArchiveEnvelope(manifest: manifest, payload: payloadData)
        )
    }

    func validateAndDecode(_ archiveData: Data) throws -> PFSSValidatedArchive {
        let envelope: PFSSArchiveEnvelope
        do {
            envelope = try Self.decoder.decode(
                PFSSArchiveEnvelope.self,
                from: archiveData
            )
        } catch {
            throw PFSSArchiveError.unreadableArchive
        }

        guard envelope.manifest.mediaType == PFSSArchiveConstants.mediaType else {
            throw PFSSArchiveError.unsupportedMediaType(
                envelope.manifest.mediaType
            )
        }
        guard envelope.manifest.archiveFormatVersion ==
                PFSSArchiveConstants.currentArchiveFormatVersion else {
            throw PFSSArchiveError.unsupportedArchiveFormat(
                found: envelope.manifest.archiveFormatVersion,
                supported: PFSSArchiveConstants.currentArchiveFormatVersion
            )
        }
        guard envelope.payload.count == envelope.manifest.payloadByteCount else {
            throw PFSSArchiveError.payloadSizeMismatch
        }
        guard Self.sha256(envelope.payload) == envelope.manifest.payloadSHA256 else {
            throw PFSSArchiveError.checksumMismatch
        }

        let migratedPayload = try migrateIfNeeded(
            envelope.payload,
            from: envelope.manifest.dataSchemaVersion
        )
        let payload: PFSSArchivePayload
        do {
            payload = try Self.decoder.decode(
                PFSSArchivePayload.self,
                from: migratedPayload
            )
        } catch {
            throw PFSSArchiveError.unreadablePayload
        }

        guard payload.recordCounts == envelope.manifest.recordCounts else {
            throw PFSSArchiveError.unreadablePayload
        }
        return PFSSValidatedArchive(
            manifest: envelope.manifest,
            payload: payload
        )
    }

    private func migrateIfNeeded(
        _ payload: Data,
        from sourceVersion: Int
    ) throws -> Data {
        let currentVersion = PFSSArchiveConstants.currentDataSchemaVersion
        guard sourceVersion <= currentVersion else {
            throw PFSSArchiveError.newerDataSchema(
                found: sourceVersion,
                supported: currentVersion
            )
        }

        var data = payload
        var version = sourceVersion
        while version < currentVersion {
            guard let migration = migrations[version] else {
                throw PFSSArchiveError.missingMigration(from: version)
            }
            guard migration.destinationSchemaVersion > version,
                  migration.destinationSchemaVersion <= currentVersion else {
                throw PFSSArchiveError.invalidMigrationPath(
                    from: version,
                    to: migration.destinationSchemaVersion
                )
            }
            data = try migration.migrate(data)
            version = migration.destinationSchemaVersion
        }
        return data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum PFSSBuildIdentity {
    static var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    static var build: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
    }
}
