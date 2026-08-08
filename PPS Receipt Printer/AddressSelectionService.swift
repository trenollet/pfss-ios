//
//  AddressSelectionService.swift
//  PPS Receipt Printer
//
//  Phase 18 – Reusable foreground map-assisted address selection.
//

import CoreLocation
import Foundation
import MapKit

struct AddressCandidate: Equatable {
    enum Source: String, Equatable {
        case currentLocation
        case selectedMapPoint
    }

    let coordinate: CLLocationCoordinate2D
    let formattedAddress: String
    let source: Source
    let horizontalAccuracy: CLLocationAccuracy?

    static func == (lhs: AddressCandidate, rhs: AddressCandidate) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.formattedAddress == rhs.formattedAddress &&
        lhs.source == rhs.source &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy
    }
}

enum AddressSelectionFailure: LocalizedError {
    case noAddressFound

    var errorDescription: String? {
        switch self {
        case .noAddressFound:
            return "PFSS could not identify a street address at that point. Select a nearby point or enter the address manually."
        }
    }
}

@MainActor
final class AddressSelectionService {
    func candidate(
        for location: CLLocation,
        source: AddressCandidate.Source
    ) async throws -> AddressCandidate {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw AddressSelectionFailure.noAddressFound
        }
        let mapItems = try await request.mapItems
        guard let mapItem = mapItems.first,
              let address = mapItem.addressRepresentations?
                .fullAddress(includingRegion: false, singleLine: true)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else {
            throw AddressSelectionFailure.noAddressFound
        }

        return AddressCandidate(
            coordinate: location.coordinate,
            formattedAddress: address,
            source: source,
            horizontalAccuracy: location.horizontalAccuracy >= 0
                ? location.horizontalAccuracy
                : nil
        )
    }

}
