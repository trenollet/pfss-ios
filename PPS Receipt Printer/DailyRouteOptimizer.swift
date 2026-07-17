//
//  DailyRouteOptimizer.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/17/26.
//

//
//  DailyRouteOptimizer.swift
//  PPS Receipt Printer
//

//
//  DailyRouteOptimizer.swift
//  PPS Receipt Printer
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

    private let geocoder = AddressGeocoder()

    func optimizedRoute(
        jobs: [JobRecord],
        sites: [CustomerSite],
        startingLocation: CLLocation
    ) async -> [JobRecord] {

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

        return nearestNeighborRoute(
            stops: routeStops,
            startingLocation: startingLocation
        )
    }

    private func nearestNeighborRoute(
        stops: [RouteStop],
        startingLocation: CLLocation
    ) -> [JobRecord] {

        var remainingStops = stops
        var optimizedJobs: [JobRecord] = []
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

            optimizedJobs.append(nearestStop.job)
            currentLocation = nearestStop.location
        }

        return optimizedJobs
    }
}
