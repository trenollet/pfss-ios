//
//  MapKitRouteTravelEstimator.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route Engine Integration
//

import Foundation
import CoreLocation
import MapKit

/// Road-network implementation of the Route Engine travel boundary.
///
/// MapKit supplies automobile distance and expected travel time. Results are
/// cached in 15-minute departure buckets because RouteEngine may evaluate the
/// same leg more than once while comparing flexible stops and building the
/// final timeline.
final class MapKitRouteTravelEstimator: RouteTravelEstimating {
    private let fallbackEstimator: RouteTravelEstimating?
    private let cache = MapKitRouteEstimateCache()

    init(fallbackEstimator: RouteTravelEstimating? = nil) {
        self.fallbackEstimator = fallbackEstimator
    }

    func estimateTravel(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        departingAt departureDate: Date
    ) async throws -> RouteTravelEstimate {
        guard origin.isValid, destination.isValid else {
            throw MapKitRouteTravelError.invalidCoordinate
        }

        let key = RouteLegCacheKey(
            origin: origin,
            destination: destination,
            departureDate: departureDate
        )

        if let cached = cache.estimate(for: key) {
            return RouteTravelEstimate(
                distanceMeters: cached.distanceMeters,
                expectedTravelTimeSeconds: cached.expectedTravelTimeSeconds,
                source: .cachedRoadNetwork
            )
        }

        do {
            let estimate = try await mapKitEstimate(
                from: origin,
                to: destination,
                departingAt: departureDate
            )
            cache.store(estimate, for: key)
            return estimate
        } catch {
            guard let fallbackEstimator else {
                if let routeError = error as? MapKitRouteTravelError {
                    throw routeError
                }
                throw MapKitRouteTravelError.directionsUnavailable(
                    error.localizedDescription
                )
            }

            return try await fallbackEstimator.estimateTravel(
                from: origin,
                to: destination,
                departingAt: departureDate
            )
        }
    }

    private func mapKitEstimate(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        departingAt departureDate: Date
    ) async throws -> RouteTravelEstimate {
        let request = MKDirections.Request()
        request.source = mapItem(for: origin)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile
        request.departureDate = departureDate
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculateETA()

        guard response.distance.isFinite,
              response.expectedTravelTime.isFinite,
              response.distance >= 0,
              response.expectedTravelTime >= 0 else {
            throw MapKitRouteTravelError.invalidResponse
        }

        return RouteTravelEstimate(
            distanceMeters: response.distance,
            expectedTravelTimeSeconds: response.expectedTravelTime,
            source: .roadNetwork
        )
    }

    private func mapItem(for coordinate: RouteCoordinate) -> MKMapItem {
        MKMapItem(
            location: CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            address: nil
        )
    }
}

enum MapKitRouteTravelError: LocalizedError {
    case invalidCoordinate
    case invalidResponse
    case directionsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "The route contains an invalid coordinate."
        case .invalidResponse:
            return "Apple Maps returned an invalid route estimate."
        case .directionsUnavailable(let message):
            return "Apple Maps could not calculate this route: \(message)"
        }
    }
}

private struct RouteLegCacheKey: Hashable {
    let originLatitude: Int
    let originLongitude: Int
    let destinationLatitude: Int
    let destinationLongitude: Int
    let departureBucket: Int

    init(
        origin: RouteCoordinate,
        destination: RouteCoordinate,
        departureDate: Date
    ) {
        // Five decimal places is approximately meter-level precision and keeps
        // insignificant floating-point differences from defeating the cache.
        originLatitude = Self.normalized(origin.latitude)
        originLongitude = Self.normalized(origin.longitude)
        destinationLatitude = Self.normalized(destination.latitude)
        destinationLongitude = Self.normalized(destination.longitude)
        departureBucket = Int(departureDate.timeIntervalSinceReferenceDate) /
            (15 * 60)
    }

    private static func normalized(_ value: Double) -> Int {
        Int((value * 100_000).rounded())
    }
}

/// The application uses Main Actor isolation by default. Keeping this small
/// in-memory cache on the estimator's actor avoids crossing an actor boundary
/// with synthesized Hashable conformances under Swift 6 strict concurrency.
private final class MapKitRouteEstimateCache {
    private var estimates: [RouteLegCacheKey: RouteTravelEstimate] = [:]

    func estimate(for key: RouteLegCacheKey) -> RouteTravelEstimate? {
        estimates[key]
    }

    func store(
        _ estimate: RouteTravelEstimate,
        for key: RouteLegCacheKey
    ) {
        estimates[key] = estimate
    }
}
