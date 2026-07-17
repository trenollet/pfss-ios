//
//  TechnicianLocationManager.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/17/26.
//

import Foundation
import CoreLocation
import Combine

enum TechnicianLocationStatus: Equatable {
    case notRequested
    case requestingPermission
    case acquiringLocation
    case ready
    case denied
    case restricted
    case servicesDisabled
    case unavailable

    var title: String {
        switch self {
        case .notRequested:
            return "GPS Not Requested"
        case .requestingPermission:
            return "Requesting Location…"
        case .acquiringLocation:
            return "Acquiring GPS…"
        case .ready:
            return "GPS Ready"
        case .denied:
            return "Location Denied"
        case .restricted:
            return "Location Restricted"
        case .servicesDisabled:
            return "Location Disabled"
        case .unavailable:
            return "Location Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .notRequested:
            return "location"
        case .requestingPermission, .acquiringLocation:
            return "location.circle"
        case .ready:
            return "location.fill"
        case .denied, .restricted:
            return "location.slash.fill"
        case .servicesDisabled:
            return "location.slash"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }
}

enum TechnicianLocationError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case permissionRestricted
    case locationUnavailable
    case requestAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location Services are turned off. Enable them in Settings to optimize the route."
        case .permissionDenied:
            return "Location access was denied. Open Settings and allow PFSS to use your location while using the app."
        case .permissionRestricted:
            return "Location access is restricted on this device."
        case .locationUnavailable:
            return "PFSS could not determine the current location. Please try again in an area with a clear GPS or network signal."
        case .requestAlreadyInProgress:
            return "PFSS is already trying to determine the current location."
        }
    }
}

final class TechnicianLocationManager: NSObject,
                                       ObservableObject,
                                       CLLocationManagerDelegate {

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocation?
    @Published var locationError: Error?
    @Published private(set) var status: TechnicianLocationStatus

    private let manager = CLLocationManager()
    private var pendingLocationCompletion: ((Result<CLLocation, Error>) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        status = Self.initialStatus(
            authorizationStatus: manager.authorizationStatus
        )

        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Public

    func requestLocationAccess() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .servicesDisabled
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            status = .requestingPermission
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways,
             .authorizedWhenInUse:
            status = .acquiringLocation
            manager.requestLocation()

        case .denied:
            status = .denied

        case .restricted:
            status = .restricted

        @unknown default:
            status = .unavailable
        }
    }

    func refreshLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .servicesDisabled
            return
        }

        guard manager.authorizationStatus == .authorizedAlways ||
              manager.authorizationStatus == .authorizedWhenInUse
        else {
            updateStatusForCurrentAuthorization()
            return
        }

        status = .acquiringLocation
        manager.requestLocation()
    }

    /// Requests permission when necessary and returns one current location.
    /// The completion remains pending while the system permission prompt is visible.
    func requestCurrentLocation(
        completion: @escaping (Result<CLLocation, Error>) -> Void
    ) {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .servicesDisabled
            completion(.failure(TechnicianLocationError.servicesDisabled))
            return
        }

        guard pendingLocationCompletion == nil else {
            completion(.failure(TechnicianLocationError.requestAlreadyInProgress))
            return
        }

        pendingLocationCompletion = completion
        locationError = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            status = .requestingPermission
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways,
             .authorizedWhenInUse:
            status = .acquiringLocation
            manager.requestLocation()

        case .denied:
            status = .denied
            finishRequest(
                with: .failure(TechnicianLocationError.permissionDenied)
            )

        case .restricted:
            status = .restricted
            finishRequest(
                with: .failure(TechnicianLocationError.permissionRestricted)
            )

        @unknown default:
            status = .unavailable
            finishRequest(
                with: .failure(TechnicianLocationError.locationUnavailable)
            )
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        authorizationStatus = manager.authorizationStatus

        guard CLLocationManager.locationServicesEnabled() else {
            currentLocation = nil
            status = .servicesDisabled
            finishRequest(
                with: .failure(TechnicianLocationError.servicesDisabled)
            )
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways,
             .authorizedWhenInUse:
            status = .acquiringLocation
            manager.requestLocation()

        case .denied:
            currentLocation = nil
            status = .denied
            finishRequest(
                with: .failure(TechnicianLocationError.permissionDenied)
            )

        case .restricted:
            currentLocation = nil
            status = .restricted
            finishRequest(
                with: .failure(TechnicianLocationError.permissionRestricted)
            )

        case .notDetermined:
            status = pendingLocationCompletion == nil
                ? .notRequested
                : .requestingPermission

        @unknown default:
            currentLocation = nil
            status = .unavailable
            finishRequest(
                with: .failure(TechnicianLocationError.locationUnavailable)
            )
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            status = .unavailable
            finishRequest(
                with: .failure(TechnicianLocationError.locationUnavailable)
            )
            return
        }

        currentLocation = location
        locationError = nil
        status = .ready
        finishRequest(with: .success(location))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        locationError = error
        status = .unavailable

        if let coreLocationError = error as? CLError,
           coreLocationError.code == .locationUnknown {
            finishRequest(
                with: .failure(TechnicianLocationError.locationUnavailable)
            )
        } else {
            finishRequest(with: .failure(error))
        }
    }

    // MARK: - Private

    private static func initialStatus(
        authorizationStatus: CLAuthorizationStatus
    ) -> TechnicianLocationStatus {
        guard CLLocationManager.locationServicesEnabled() else {
            return .servicesDisabled
        }

        switch authorizationStatus {
        case .notDetermined:
            return .notRequested
        case .authorizedAlways, .authorizedWhenInUse:
            return .acquiringLocation
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    private func updateStatusForCurrentAuthorization() {
        status = Self.initialStatus(
            authorizationStatus: manager.authorizationStatus
        )
    }

    private func finishRequest(
        with result: Result<CLLocation, Error>
    ) {
        guard let completion = pendingLocationCompletion else {
            return
        }

        pendingLocationCompletion = nil
        completion(result)
    }
}
