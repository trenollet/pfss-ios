//
//  PFSSICloudArchiveService.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 3 – iCloud Drive archive synchronization and recovery.
//

import Combine
import Foundation

enum PFSSICloudAvailability: Equatable {
    case checking
    case available
    case signedOut
    case containerUnavailable
    case failed(String)

    var title: String {
        switch self {
        case .checking: return "Checking iCloud"
        case .available: return "iCloud Available"
        case .signedOut: return "Sign In to iCloud"
        case .containerUnavailable: return "iCloud Drive Unavailable"
        case .failed: return "iCloud Error"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "PFSS is checking this device's iCloud availability."
        case .available:
            return "Backups can synchronize through the signed-in Apple account."
        case .signedOut:
            return "Sign in to iCloud in Settings before using iCloud backup."
        case .containerUnavailable:
            return "Turn on iCloud Drive for PFSS, then try again."
        case let .failed(message):
            return message
        }
    }
}

struct PFSSICloudArchive: Identifiable, Hashable {
    var id: URL { fileURL }
    var fileURL: URL
    var createdAt: Date
    var byteCount: Int64
}

enum PFSSICloudArchiveError: LocalizedError, Equatable {
    case signedOut
    case containerUnavailable
    case noBackup
    case unableToCreateDirectory(String)
    case unableToWrite(String)
    case unableToRead(String)

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "This device is not signed in to iCloud."
        case .containerUnavailable:
            return "The PFSS iCloud Drive container is unavailable."
        case .noBackup:
            return "No PFSS backup is currently available in iCloud."
        case let .unableToCreateDirectory(message):
            return "PFSS could not create its iCloud backup folder: \(message)"
        case let .unableToWrite(message):
            return "PFSS could not save the iCloud backup: \(message)"
        case let .unableToRead(message):
            return "PFSS could not read the iCloud backup: \(message)"
        }
    }
}

protocol PFSSICloudArchiveTransport {
    func availability() -> PFSSICloudAvailability
    func upload(_ archiveData: Data, createdAt: Date) throws -> PFSSICloudArchive
    func availableArchives() throws -> [PFSSICloudArchive]
    func data(for archive: PFSSICloudArchive) throws -> Data
}

struct PFSSICloudDriveArchiveTransport: PFSSICloudArchiveTransport {
    private let fileManager: FileManager
    private let containerURLProvider: () -> URL?
    private let identityAvailable: () -> Bool
    private let retainedBackupCount: Int

    init(
        fileManager: FileManager = .default,
        retainedBackupCount: Int = 10,
        containerURLProvider: (() -> URL?)? = nil,
        identityAvailable: (() -> Bool)? = nil
    ) {
        self.fileManager = fileManager
        self.retainedBackupCount = max(retainedBackupCount, 1)
        self.containerURLProvider = containerURLProvider ?? {
            fileManager.url(forUbiquityContainerIdentifier: nil)
        }
        self.identityAvailable = identityAvailable ?? {
            fileManager.ubiquityIdentityToken != nil
        }
    }

    func availability() -> PFSSICloudAvailability {
        guard identityAvailable() else { return .signedOut }
        guard containerURLProvider() != nil else { return .containerUnavailable }
        return .available
    }

    func upload(
        _ archiveData: Data,
        createdAt: Date = Date()
    ) throws -> PFSSICloudArchive {
        let directory = try backupDirectory()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PFSSICloudArchiveError.unableToCreateDirectory(
                error.localizedDescription
            )
        }

        let name = "PFSS-iCloud-\(Self.fileDateFormatter.string(from: createdAt))-\(UUID().uuidString.prefix(8))"
        let url = directory
            .appendingPathComponent(name)
            .appendingPathExtension(PFSSArchiveConstants.fileExtension)
        do {
            try archiveData.write(to: url, options: [.atomic])
            try? fileManager.setAttributes(
                [.modificationDate: createdAt],
                ofItemAtPath: url.path
            )
        } catch {
            throw PFSSICloudArchiveError.unableToWrite(
                error.localizedDescription
            )
        }

        pruneOldBackups()
        return archive(for: url, fallbackDate: createdAt)
    }

    func availableArchives() throws -> [PFSSICloudArchive] {
        let directory = try backupDirectory()
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .creationDateKey,
                    .contentModificationDateKey,
                    .fileSizeKey
                ],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == PFSSArchiveConstants.fileExtension }
            .map { archive(for: $0, fallbackDate: .distantPast) }
            .sorted { $0.createdAt > $1.createdAt }
        } catch {
            throw PFSSICloudArchiveError.unableToRead(
                error.localizedDescription
            )
        }
    }

    func data(for archive: PFSSICloudArchive) throws -> Data {
        do {
            let isUbiquitous = try archive.fileURL.resourceValues(
                forKeys: [.isUbiquitousItemKey]
            ).isUbiquitousItem ?? false
            if isUbiquitous {
                try fileManager.startDownloadingUbiquitousItem(
                    at: archive.fileURL
                )
            }
            return try Data(contentsOf: archive.fileURL)
        } catch {
            throw PFSSICloudArchiveError.unableToRead(
                error.localizedDescription
            )
        }
    }

    private func backupDirectory() throws -> URL {
        guard identityAvailable() else { throw PFSSICloudArchiveError.signedOut }
        guard let container = containerURLProvider() else {
            throw PFSSICloudArchiveError.containerUnavailable
        }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("PFSS", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private func archive(
        for url: URL,
        fallbackDate: Date
    ) -> PFSSICloudArchive {
        let values = try? url.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey
        ])
        return PFSSICloudArchive(
            fileURL: url,
            createdAt: values?.contentModificationDate ??
                values?.creationDate ?? fallbackDate,
            byteCount: Int64(values?.fileSize ?? 0)
        )
    }

    private func pruneOldBackups() {
        guard let archives = try? availableArchives(),
              archives.count > retainedBackupCount else { return }
        for archive in archives.dropFirst(retainedBackupCount) {
            try? fileManager.removeItem(at: archive.fileURL)
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

@MainActor
final class PFSSICloudArchiveManager: ObservableObject {
    @Published private(set) var availability: PFSSICloudAvailability = .checking
    @Published private(set) var archives: [PFSSICloudArchive] = []
    @Published private(set) var isWorking = false

    private let transport: any PFSSICloudArchiveTransport

    init(transport: (any PFSSICloudArchiveTransport)? = nil) {
        self.transport = transport ?? PFSSICloudDriveArchiveTransport()
    }

    var latestArchive: PFSSICloudArchive? { archives.first }

    func refresh() {
        availability = transport.availability()
        guard availability == .available else {
            archives = []
            return
        }
        do {
            archives = try transport.availableArchives()
        } catch {
            availability = .failed(error.localizedDescription)
            archives = []
        }
    }

    @discardableResult
    func upload(_ data: Data, createdAt: Date = Date()) throws -> PFSSICloudArchive {
        isWorking = true
        defer { isWorking = false }
        let uploaded = try transport.upload(data, createdAt: createdAt)
        refresh()
        return uploaded
    }

    func latestData() throws -> (PFSSICloudArchive, Data) {
        isWorking = true
        defer { isWorking = false }
        refresh()
        guard let latestArchive else { throw PFSSICloudArchiveError.noBackup }
        return (latestArchive, try transport.data(for: latestArchive))
    }
}
