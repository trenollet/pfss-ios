//
//  DailyRouteOptimizer.swift
//  PPS Receipt Printer
//
//  Brick 6D.1: Configurable business route planning
//

import Foundation
import CoreLocation

struct DailyRouteOptimizer {

    struct RouteStop: Identifiable {
        let job: JobRecord
        let location: CLLocation

        var id: UUID {
            job.id
        }
    }

    struct RouteSummary: Equatable {
        let stopCount: Int
        let totalDistanceMeters: CLLocationDistance
        let estimatedDriveTimeSeconds: TimeInterval
        let planningBufferSeconds: TimeInterval
        let includeBuffersInPlannedTime: Bool

        var totalDistanceMiles: Double {
            totalDistanceMeters / 1_609.344
        }

        var estimatedDriveMinutes: Int {
            roundedMinutes(
                from: estimatedDriveTimeSeconds
            )
        }

        var planningBufferMinutes: Int {
            roundedMinutes(
                from: planningBufferSeconds
            )
        }

        var plannedRouteTimeSeconds: TimeInterval {
            estimatedDriveTimeSeconds +
            (
                includeBuffersInPlannedTime
                    ? planningBufferSeconds
                    : 0
            )
        }

        var plannedRouteMinutes: Int {
            roundedMinutes(
                from: plannedRouteTimeSeconds
            )
        }

        private func roundedMinutes(
            from seconds: TimeInterval
        ) -> Int {
            max(
                0,
                Int((seconds / 60).rounded())
            )
        }
    }

    struct OptimizationResult {
        let jobs: [JobRecord]
        let summary: RouteSummary
    }

    private let geocoder = AddressGeocoder()

    func optimize(
        jobs: [JobRecord],
        sites: [CustomerSite],
        startingLocation: CLLocation,
        settings: BusinessOperationsSettings
    ) async -> OptimizationResult {

        var normalizedSettings = settings
        normalizedSettings.normalize()

        var routeStops: [RouteStop] = []

        for job in jobs {
            guard
                job.status != .completed,
                job.status != .cancelled,
                let siteID = job.siteID,
                let site = sites.first(where: {
                    $0.id == siteID
                })
            else {
                continue
            }

            let address = site.serviceAddress.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !address.isEmpty else {
                continue
            }

            do {
                let location = try await geocoder.geocode(
                    address: address
                )

                routeStops.append(
                    RouteStop(
                        job: job,
                        location: location
                    )
                )
            } catch {
                print(
                    "Unable to geocode job \(job.id): " +
                    error.localizedDescription
                )
            }
        }

        let optimizedStops = nearestNeighborRoute(
            stops: routeStops,
            startingLocation: startingLocation
        )

        let totalDistance = routeDistance(
            stops: optimizedStops,
            startingLocation: startingLocation
        )

        let speedMetersPerSecond =
            normalizedSettings.averageDrivingSpeedMPH *
            0.44704

        let estimatedDriveTime = speedMetersPerSecond > 0
            ? totalDistance / speedMetersPerSecond
            : 0

        let totalBufferMinutes =
            normalizedSettings.dailyRouteBufferMinutes +
            (
                normalizedSettings.perStopBufferMinutes *
                optimizedStops.count
            )

        return OptimizationResult(
            jobs: optimizedStops.map(\.job),
            summary: RouteSummary(
                stopCount: optimizedStops.count,
                totalDistanceMeters: totalDistance,
                estimatedDriveTimeSeconds: estimatedDriveTime,
                planningBufferSeconds:
                    TimeInterval(totalBufferMinutes * 60),
                includeBuffersInPlannedTime:
                    normalizedSettings
                        .includeBuffersInRouteTime
            )
        )
    }

    func optimizedRoute(
        jobs: [JobRecord],
        sites: [CustomerSite],
        startingLocation: CLLocation,
        settings: BusinessOperationsSettings
    ) async -> [JobRecord] {
        let result = await optimize(
            jobs: jobs,
            sites: sites,
            startingLocation: startingLocation,
            settings: settings
        )

        return result.jobs
    }

    private func nearestNeighborRoute(
        stops: [RouteStop],
        startingLocation: CLLocation
    ) -> [RouteStop] {

        var remainingStops = stops
        var optimizedStops: [RouteStop] = []
        var currentLocation = startingLocation

        while !remainingStops.isEmpty {
            guard let nearestIndex = remainingStops.indices.min(
                by: { firstIndex, secondIndex in
                    let firstDistance = currentLocation.distance(
                        from: remainingStops[firstIndex].location
                    )

                    let secondDistance = currentLocation.distance(
                        from: remainingStops[secondIndex].location
                    )

                    return firstDistance < secondDistance
                }
            ) else {
                break
            }

            let nearestStop = remainingStops.remove(
                at: nearestIndex
            )

            optimizedStops.append(nearestStop)
            currentLocation = nearestStop.location
        }

        return optimizedStops
    }

    private func routeDistance(
        stops: [RouteStop],
        startingLocation: CLLocation
    ) -> CLLocationDistance {

        var totalDistance: CLLocationDistance = 0
        var currentLocation = startingLocation

        for stop in stops {
            totalDistance += currentLocation.distance(
                from: stop.location
            )
            currentLocation = stop.location
        }

        return totalDistance
    }
}
