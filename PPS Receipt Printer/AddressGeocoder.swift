//
//  AddressGeocoder.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/17/26.
//

//
//  AddressGeocoder.swift
//  PPS Receipt Printer
//

//
//  AddressGeocoder.swift
//  PPS Receipt Printer
//

import Foundation
import CoreLocation
import MapKit

final class AddressGeocoder {

    func geocode(
        address: String
    ) async throws -> CLLocation {

        let cleanedAddress = address.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedAddress.isEmpty else {
            throw GeocoderError.invalidAddress
        }

        guard let request = MKGeocodingRequest(
            addressString: cleanedAddress
        ) else {
            throw GeocoderError.invalidAddress
        }

        let mapItems = try await request.mapItems

        guard let mapItem = mapItems.first else {
            throw GeocoderError.locationNotFound
        }

        return mapItem.location
    }
}

extension AddressGeocoder {

    enum GeocoderError: LocalizedError {

        case invalidAddress
        case locationNotFound

        var errorDescription: String? {
            switch self {

            case .invalidAddress:
                return "The address is empty or invalid."

            case .locationNotFound:
                return "Unable to locate the address."
            }
        }
    }
}
