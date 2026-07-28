//
//  OperationalRecommendationTravelResolver.swift
//  PPS Receipt Printer
//
//  Route-aware evidence for explainable Dispatch Queue recommendations.
//

import Foundation
import CoreLocation

@MainActor
final class OperationalRecommendationTravelResolver {
    static let shared = OperationalRecommendationTravelResolver()

    private let geocoder = AddressGeocoder()
    private let estimator = MapKitRouteTravelEstimator()
    private var coordinateCache: [String: RouteCoordinate] = [:]
    private var travelEvidenceCache: [TravelCacheKey: OperationalTravelEvidence] = [:]

    private init() { }

    func evidence(
        for targetJob: JobRecord,
        candidates: [OperationalRecommendationCandidate],
        jobs: [JobRecord],
        sites: [CustomerSite],
        employees: [EmployeeRecord]
    ) async -> [UUID: OperationalTravelEvidence] {
        guard let destinationAddress = address(for: targetJob, sites: sites),
              let destination = await coordinate(for: destinationAddress) else {
            return [:]
        }

        var result: [UUID: OperationalTravelEvidence] = [:]
        for candidate in candidates {
            let departure = candidate.proposedStartDate ?? targetJob.scheduledDate
            let employee = employees.first { $0.id == candidate.employeeID }
            guard let origin = await resolvedOrigin(
                for: candidate.employeeID,
                before: departure,
                excluding: targetJob.id,
                jobs: jobs,
                sites: sites,
                employee: employee
            ) else {
                result[candidate.employeeID] = OperationalTravelEvidence(
                    isLocationResolved: false,
                    warningMessages: [
                        "Travel unavailable: no previous-stop or employee base address."
                    ]
                )
                continue
            }

            let cacheKey = TravelCacheKey(
                originAddress: normalized(origin.address),
                destinationAddress: normalized(destinationAddress),
                departureBucket: Int(departure.timeIntervalSince1970 / 900)
            )
            if let cached = travelEvidenceCache[cacheKey] {
                result[candidate.employeeID] = cached
                continue
            }

            do {
                let estimate = try await estimator.estimateTravel(
                    from: origin.coordinate,
                    to: destination,
                    departingAt: departure
                )
                let evidence = OperationalTravelEvidence(
                    distanceMiles: estimate.distanceMiles,
                    travelMinutes: estimate.expectedTravelMinutes,
                    source: estimate.source,
                    isLocationResolved: true,
                    warningMessages: [
                        "Route origin: \(origin.label) — \(origin.address)"
                    ]
                )
                travelEvidenceCache[cacheKey] = evidence
                result[candidate.employeeID] = evidence
            } catch {
                result[candidate.employeeID] = OperationalTravelEvidence(
                    isLocationResolved: false,
                    warningMessages: [error.localizedDescription]
                )
            }
        }
        return result
    }

    private struct ResolvedOrigin {
        var coordinate: RouteCoordinate
        var address: String
        var label: String
    }

    private struct TravelCacheKey: Hashable {
        var originAddress: String
        var destinationAddress: String
        var departureBucket: Int
    }

    private func resolvedOrigin(
        for employeeID: UUID,
        before date: Date,
        excluding jobID: UUID,
        jobs: [JobRecord],
        sites: [CustomerSite],
        employee: EmployeeRecord?
    ) async -> ResolvedOrigin? {
        if let originJob = precedingJob(
            for: employeeID,
            before: date,
            excluding: jobID,
            jobs: jobs
        ),
        let originAddress = address(for: originJob, sites: sites),
        let originCoordinate = await coordinate(for: originAddress) {
            return ResolvedOrigin(
                coordinate: originCoordinate,
                address: originAddress,
                label: "previous stop"
            )
        }

        if let baseAddress = employee?.normalizedBaseAddress,
           let baseCoordinate = await coordinate(for: baseAddress) {
            return ResolvedOrigin(
                coordinate: baseCoordinate,
                address: baseAddress,
                label: "employee base"
            )
        }

        return nil
    }

    private func precedingJob(
        for employeeID: UUID,
        before date: Date,
        excluding jobID: UUID,
        jobs: [JobRecord]
    ) -> JobRecord? {
        jobs.filter {
            $0.id != jobID &&
            ($0.primaryTechnicianID == employeeID ||
                $0.secondaryTechnicianID == employeeID) &&
            $0.scheduledDate <= date
        }
        .max { $0.scheduledDate < $1.scheduledDate }
    }

    private func address(
        for job: JobRecord,
        sites: [CustomerSite]
    ) -> String? {
        guard let site = sites.first(where: { $0.id == job.siteID }) else {
            return nil
        }
        let address = site.serviceAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return address.isEmpty ? nil : address
    }

    private func coordinate(for address: String) async -> RouteCoordinate? {
        let key = normalized(address)
        if let cached = coordinateCache[key] { return cached }
        do {
            let location = try await geocoder.geocode(address: address)
            let coordinate = RouteCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            guard coordinate.isValid else { return nil }
            coordinateCache[key] = coordinate
            return coordinate
        } catch {
            return nil
        }
    }

    private func normalized(_ address: String) -> String {
        address.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
