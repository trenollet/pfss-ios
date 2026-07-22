//
//  RouteLocationResolver.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route Engine Integration
//

import Foundation
import CoreLocation

/// Resolves Assignment service sites into Route Engine coordinates.
///
/// A failed address is intentionally omitted from the returned location list.
/// RouteEngine then reports that Assignment as an explicit missing-location
/// conflict and keeps its ID in unrouteableAssignmentIDs.
final class RouteLocationResolver {
    private let geocoder: AddressGeocoder
    private let cache = RouteLocationCache()

    init(geocoder: AddressGeocoder = AddressGeocoder()) {
        self.geocoder = geocoder
    }

    func resolveLocations(
        for assignments: [Assignment],
        sites: [CustomerSite]
    ) async -> [RouteAssignmentLocation] {
        let sitesByID = Dictionary(
            uniqueKeysWithValues: sites.map { ($0.id, $0) }
        )
        var resolved: [RouteAssignmentLocation] = []

        for assignment in assignments.sorted(by: stableAssignmentOrder) {
            guard let siteID = assignment.siteID,
                  let site = sitesByID[siteID] else {
                continue
            }

            let address = site.serviceAddress.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !address.isEmpty else { continue }

            if let cached = await cache.coordinate(for: address) {
                resolved.append(
                    RouteAssignmentLocation(
                        assignmentID: assignment.id,
                        coordinate: cached,
                        displayAddress: address
                    )
                )
                continue
            }

            do {
                let location = try await geocoder.geocode(address: address)
                let coordinate = RouteCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                guard coordinate.isValid else { continue }

                await cache.store(coordinate, for: address)
                resolved.append(
                    RouteAssignmentLocation(
                        assignmentID: assignment.id,
                        coordinate: coordinate,
                        displayAddress: address
                    )
                )
            } catch {
                // RouteEngine owns the user-visible missing-location conflict.
                // A single failed address must not prevent other stops routing.
                continue
            }
        }

        return resolved
    }

    private func stableAssignmentOrder(
        _ first: Assignment,
        _ second: Assignment
    ) -> Bool {
        if first.assignmentNumber != second.assignmentNumber {
            return first.assignmentNumber.localizedStandardCompare(
                second.assignmentNumber
            ) == .orderedAscending
        }
        return first.id.uuidString < second.id.uuidString
    }
}

private actor RouteLocationCache {
    private var coordinates: [String: RouteCoordinate] = [:]

    func coordinate(for address: String) -> RouteCoordinate? {
        coordinates[normalized(address)]
    }

    func store(_ coordinate: RouteCoordinate, for address: String) {
        coordinates[normalized(address)] = coordinate
    }

    private func normalized(_ address: String) -> String {
        address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
