//
//  PFSSLocalBackupService.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 2 – Local backup storage and portable document support.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pfssArchive = UTType(
        exportedAs: "com.pfss.archive",
        conformingTo: .json
    )
}

struct PFSSArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pfssArchive] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw PFSSArchiveError.unreadableArchive
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum PFSSLocalBackupKind: String, Codable, Hashable {
    case manual
    case preRestoreSafety

    var title: String {
        switch self {
        case .manual: return "Manual Backup"
        case .preRestoreSafety: return "Pre-Restore Safety Backup"
        }
    }
}

struct PFSSLocalBackup: Identifiable, Hashable {
    var id: URL { fileURL }
    var fileURL: URL
    var kind: PFSSLocalBackupKind
    var createdAt: Date
    var byteCount: Int64
}

struct PFSSRestoreResult {
    var restoredManifest: PFSSArchiveManifest
    var safetyBackup: PFSSLocalBackup
}

enum PFSSRestoreError: LocalizedError {
    case restoreFailed(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case let .restoreFailed(message):
            return "The backup was not restored. Current data was preserved: \(message)"
        case let .rollbackFailed(message):
            return "Restore failed and PFSS could not complete its automatic rollback: \(message)"
        }
    }
}

enum PFSSLocalBackupError: LocalizedError {
    case unableToCreateDirectory(String)
    case unableToWrite(String)
    case unableToRead(String)
    case unableToRemove(String)

    var errorDescription: String? {
        switch self {
        case let .unableToCreateDirectory(message):
            return "PFSS could not create its backup folder: \(message)"
        case let .unableToWrite(message):
            return "PFSS could not save the local backup: \(message)"
        case let .unableToRead(message):
            return "PFSS could not read the local backup: \(message)"
        case let .unableToRemove(message):
            return "PFSS could not remove local company backups: \(message)"
        }
    }
}

struct PFSSLocalBackupService {
    private let fileManager: FileManager
    let directoryURL: URL

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        self.directoryURL = directoryURL ?? base
            .appendingPathComponent("PFSS", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    @discardableResult
    func save(
        _ archiveData: Data,
        kind: PFSSLocalBackupKind,
        createdAt: Date = Date()
    ) throws -> PFSSLocalBackup {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PFSSLocalBackupError.unableToCreateDirectory(
                error.localizedDescription
            )
        }

        let fileURL = uniqueFileURL(kind: kind, createdAt: createdAt)
        do {
            try archiveData.write(to: fileURL, options: [.atomic])
        } catch {
            throw PFSSLocalBackupError.unableToWrite(
                error.localizedDescription
            )
        }
        return backup(for: fileURL, kind: kind, fallbackDate: createdAt)
    }

    func data(for backup: PFSSLocalBackup) throws -> Data {
        do {
            return try Data(contentsOf: backup.fileURL)
        } catch {
            throw PFSSLocalBackupError.unableToRead(
                error.localizedDescription
            )
        }
    }

    func availableBackups() -> [PFSSLocalBackup] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == PFSSArchiveConstants.fileExtension else {
                return nil
            }
            let kind: PFSSLocalBackupKind = url.lastPathComponent
                .hasPrefix("pre-restore-") ? .preRestoreSafety : .manual
            return backup(for: url, kind: kind, fallbackDate: .distantPast)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func removeAllBackups() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw PFSSLocalBackupError.unableToRemove(
                error.localizedDescription
            )
        }
    }

    private func uniqueFileURL(
        kind: PFSSLocalBackupKind,
        createdAt: Date
    ) -> URL {
        let prefix = kind == .preRestoreSafety ? "pre-restore" : "backup"
        let stamp = Self.fileDateFormatter.string(from: createdAt)
        let baseName = "\(prefix)-\(stamp)"
        var candidate = directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(PFSSArchiveConstants.fileExtension)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension(PFSSArchiveConstants.fileExtension)
            suffix += 1
        }
        return candidate
    }

    private func backup(
        for url: URL,
        kind: PFSSLocalBackupKind,
        fallbackDate: Date
    ) -> PFSSLocalBackup {
        let values = try? url.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey
        ])
        return PFSSLocalBackup(
            fileURL: url,
            kind: kind,
            createdAt: values?.creationDate ??
                values?.contentModificationDate ?? fallbackDate,
            byteCount: Int64(values?.fileSize ?? 0)
        )
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
