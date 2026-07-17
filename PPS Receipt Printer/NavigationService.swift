//
//  NavigationService.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/17/26.
//

import Foundation
import MapKit
import CoreLocation
import UIKit

@MainActor
final class NavigationService {

    static let shared = NavigationService()

    private let geocoder = AddressGeocoder()

    private init() { }

    // MARK: - Apple Maps

    func navigateWithAppleMaps(
        to site: CustomerSite
    ) async throws {
        try await navigateWithAppleMaps(
            to: site.serviceAddress
        )
    }

    func navigateWithAppleMaps(
        to address: String
    ) async throws {

        let location = try await validatedLocation(
            for: address
        )

        let mapItem = MKMapItem(
            location: location,
            address: nil
        )

        mapItem.name = address

        mapItem.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey:
                    MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }

    // MARK: - Google Maps

    func navigateWithGoogleMaps(
        to address: String
    ) async throws {

        let location = try await validatedLocation(
            for: address
        )

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        let appURL = URL(
            string:
                "comgooglemaps://?daddr=\(latitude),\(longitude)&directionsmode=driving"
        )

        let webURL = URL(
            string:
                "https://www.google.com/maps/dir/?api=1&destination=\(latitude),\(longitude)&travelmode=driving"
        )

        if let appURL,
           UIApplication.shared.canOpenURL(appURL) {

            await UIApplication.shared.open(appURL)

        } else if let webURL {

            await UIApplication.shared.open(webURL)
        }
    }

    // MARK: - Shared Validation

    private func validatedLocation(
        for address: String
    ) async throws -> CLLocation {

        let trimmed = address.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            throw NavigationError.invalidAddress
        }

        return try await geocoder.geocode(
            address: trimmed
        )
    }
}

// MARK: - Errors

enum NavigationError: LocalizedError {

    case invalidAddress

    var errorDescription: String? {

        switch self {

        case .invalidAddress:
            return "The service address is empty."
        }
    }
}
