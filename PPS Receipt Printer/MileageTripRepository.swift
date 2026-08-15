//
//  MileageTripRepository.swift
//  PPS Receipt Printer
//
//  Phase 19 – User-private, offline-first mileage persistence.
//

import Combine
import Foundation

@MainActor
final class MileageTripRepository: ObservableObject {
    static let shared = MileageTripRepository()

    @Published private(set) var trips: [MileageTrip] = []

    private struct StoredMileageData: Codable {
        var trips: [MileageTrip]
        var activeEngine: MileageDetectionEngine?
        var pendingTripIDs: Set<UUID>?
        var deletionTombstones: [UUID: Date]?
        var cloudCursor: Int?
    }

    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var context: MileageTrackingContext?
    private var activeEngine: MileageDetectionEngine?
    private var pendingTripIDs: Set<UUID> = []
    private var deletionTombstones: [UUID: Date] = [:]
    private var cloudCursor = 0
    private let cloudSynchronizationEnabled: Bool
    private var pollingTask: Task<Void, Never>?
    private var scheduledSyncTask: Task<Void, Never>?

    init(baseDirectory: URL? = nil) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        cloudSynchronizationEnabled = baseDirectory == nil
        self.baseDirectory = baseDirectory ?? applicationSupport
            .appendingPathComponent("PFSS", isDirectory: true)
            .appendingPathComponent("Mileage", isDirectory: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    var unclassifiedTrips: [MileageTrip] {
        trips
            .filter { $0.classification == .unclassified }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var classifiedTrips: [MileageTrip] {
        trips
            .filter { $0.classification != .unclassified }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var configuredContext: MileageTrackingContext? {
        context
    }

    func monthToDateMileageMiles(
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            return 0
        }
        return trips
            .filter {
                $0.startedAt >= monthInterval.start &&
                $0.startedAt < monthInterval.end &&
                $0.startedAt <= date
            }
            .reduce(0) { $0 + $1.distanceMiles }
    }

    func configure(context: MileageTrackingContext) throws {
        guard self.context != context else { return }
        pollingTask?.cancel()
        scheduledSyncTask?.cancel()
        self.context = context
        try load()
        startCloudSynchronizationIfNeeded()
    }

    func restoredEngine() -> MileageDetectionEngine? {
        activeEngine
    }

    func checkpoint(engine: MileageDetectionEngine?) throws {
        activeEngine = engine
        try persist()
    }

    func save(_ trip: MileageTrip) throws {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        } else {
            trips.append(trip)
        }
        pendingTripIDs.insert(trip.id)
        deletionTombstones.removeValue(forKey: trip.id)
        activeEngine = nil
        try persist()
        scheduleCloudSynchronization()
    }

    func classify(
        tripID: UUID,
        as classification: MileageTripClassification,
        at date: Date = Date()
    ) throws {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else {
            return
        }
        let previous = trips[index].classification
        guard previous != classification else { return }
        trips[index].classificationHistory.append(
            MileageTripClassificationChange(
                previousValue: previous,
                newValue: classification,
                changedAt: date
            )
        )
        trips[index].classification = classification
        trips[index].classifiedAt = classification == .unclassified
            ? nil
            : date
        trips[index].updatedAt = date
        pendingTripIDs.insert(tripID)
        try persist()
        scheduleCloudSynchronization()
    }

    func update(
        tripID: UUID,
        businessPurpose: String,
        note: String,
        at date: Date = Date()
    ) throws {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else {
            return
        }
        trips[index].businessPurpose = businessPurpose
        trips[index].note = note
        trips[index].updatedAt = date
        pendingTripIDs.insert(tripID)
        try persist()
        scheduleCloudSynchronization()
    }

    func markExported(
        tripIDs: Set<UUID>,
        at date: Date = Date()
    ) throws {
        guard !tripIDs.isEmpty else { return }
        for index in trips.indices where tripIDs.contains(trips[index].id) {
            trips[index].exportedAt = date
            trips[index].updatedAt = date
        }
        pendingTripIDs.formUnion(tripIDs)
        try persist()
        scheduleCloudSynchronization()
    }

    func delete(tripID: UUID) throws {
        trips.removeAll { $0.id == tripID }
        pendingTripIDs.remove(tripID)
        deletionTombstones[tripID] = Date()
        try persist()
        scheduleCloudSynchronization()
    }

    func removeCurrentUserData() throws {
        guard let fileURL else { return }
        trips = []
        activeEngine = nil
        pendingTripIDs = []
        deletionTombstones = [:]
        cloudCursor = 0
        pollingTask?.cancel()
        scheduledSyncTask?.cancel()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private var fileURL: URL? {
        guard let context else { return nil }
        return baseDirectory.appendingPathComponent(
            "\(context.accountID.uuidString.lowercased())-\(context.userID.uuidString.lowercased()).json"
        )
    }

    private func load() throws {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            trips = []
            activeEngine = nil
            pendingTripIDs = []
            deletionTombstones = [:]
            cloudCursor = 0
            return
        }
        let data = try Data(contentsOf: fileURL)
        let stored = try decoder.decode(StoredMileageData.self, from: data)
        trips = stored.trips
        activeEngine = stored.activeEngine
        pendingTripIDs = stored.pendingTripIDs ?? Set(stored.trips.map(\.id))
        deletionTombstones = stored.deletionTombstones ?? [:]
        cloudCursor = stored.cloudCursor ?? 0
    }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(
            StoredMileageData(
                trips: trips,
                activeEngine: activeEngine,
                pendingTripIDs: pendingTripIDs,
                deletionTombstones: deletionTombstones,
                cloudCursor: cloudCursor
            )
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func synchronizeWithCloud() async {
        guard cloudSynchronizationEnabled, context != nil else { return }
        let manager = PFSSCloudflareBetaManager()
        guard manager.isEnrolled else { return }
        do {
            var hasMore = true
            var firstPage = true
            while hasMore {
                let uploadIDs = firstPage ? Array(pendingTripIDs.prefix(100)) : []
                let uploads = trips.filter { uploadIDs.contains($0.id) }
                let deletions: [UUID: Date] = firstPage
                    ? Dictionary(uniqueKeysWithValues:
                        deletionTombstones.prefix(100).map { ($0.key, $0.value) })
                    : [:]
                let response = try await manager.synchronizeMileageTrips(
                    cursor: cloudCursor,
                    trips: uploads,
                    deletions: deletions
                )
                merge(response.changes)
                cloudCursor = response.cursor
                pendingTripIDs.subtract(uploadIDs)
                for id in deletions.keys {
                    deletionTombstones.removeValue(forKey: id)
                }
                try persist()
                hasMore = response.hasMore
                firstPage = false
            }
            if !pendingTripIDs.isEmpty || !deletionTombstones.isEmpty {
                scheduleCloudSynchronization(delayNanoseconds: 250_000_000)
            }
        } catch {
            // Local records and tombstones remain durable for the next retry.
        }
    }

    private func merge(_ changes: [PFSSMileageSynchronizationChange]) {
        for change in changes {
            switch change.type {
            case .upsert:
                guard let remote = change.payload else { continue }
                if let index = trips.firstIndex(where: { $0.id == remote.id }) {
                    if trips[index].updatedAt <= remote.updatedAt {
                        trips[index] = remote
                        pendingTripIDs.remove(remote.id)
                        deletionTombstones.removeValue(forKey: remote.id)
                    }
                } else if deletionTombstones[remote.id].map({
                    $0 >= remote.updatedAt
                }) != true {
                    trips.append(remote)
                }
            case .delete:
                if let local = trips.first(where: { $0.id == change.tripID }),
                   local.updatedAt > change.changedAt {
                    pendingTripIDs.insert(local.id)
                } else {
                    trips.removeAll { $0.id == change.tripID }
                    pendingTripIDs.remove(change.tripID)
                    deletionTombstones.removeValue(forKey: change.tripID)
                }
            }
        }
    }

    private func startCloudSynchronizationIfNeeded() {
        guard cloudSynchronizationEnabled else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronizeWithCloud()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func scheduleCloudSynchronization(
        delayNanoseconds: UInt64 = 1_000_000_000
    ) {
        guard cloudSynchronizationEnabled else { return }
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.synchronizeWithCloud()
        }
    }
}
