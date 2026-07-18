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

    private let manager: CLLocationManager
    private var pendingLocationCompletion:
        ((Result<CLLocation, Error>) -> Void)?

    override init() {
        manager = CLLocationManager()
        authorizationStatus = .notDetermined
        currentLocation = nil
        locationError = nil
        status = .notRequested

        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Public

    func requestLocationAccess() {
        checkLocationServices { [weak self] servicesEnabled in
            guard let self else {
                return
            }

            guard servicesEnabled else {
                self.handleServicesDisabled()
                return
            }

            self.performLocationAccessRequest()
        }
    }

    func refreshLocation() {
        checkLocationServices { [weak self] servicesEnabled in
            guard let self else {
                return
            }

            guard servicesEnabled else {
                self.handleServicesDisabled()
                return
            }

            switch self.authorizationStatus {
            case .authorizedAlways,
                 .authorizedWhenInUse:
                self.status = .acquiringLocation
                self.manager.requestLocation()

            case .notDetermined:
                self.status = .notRequested

            case .denied:
                self.status = .denied

            case .restricted:
                self.status = .restricted

            @unknown default:
                self.status = .unavailable
            }
        }
    }

    /// Requests permission when necessary and returns one current location.
    /// The completion remains pending while the system permission prompt is visible.
    func requestCurrentLocation(
        completion: @escaping (Result<CLLocation, Error>) -> Void
    ) {
        guard pendingLocationCompletion == nil else {
            completion(
                .failure(
                    TechnicianLocationError.requestAlreadyInProgress
                )
            )
            return
        }

        pendingLocationCompletion = completion
        locationError = nil

        checkLocationServices { [weak self] servicesEnabled in
            guard let self else {
                return
            }

            guard servicesEnabled else {
                self.handleServicesDisabled()
                return
            }

            self.performCurrentLocationRequest()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let newAuthorizationStatus = manager.authorizationStatus
        authorizationStatus = newAuthorizationStatus

        switch newAuthorizationStatus {
        case .authorizedAlways,
             .authorizedWhenInUse:
            if pendingLocationCompletion != nil ||
                status == .requestingPermission {
                status = .acquiringLocation
                manager.requestLocation()
            } else if currentLocation != nil {
                status = .ready
            } else {
                status = .notRequested
            }

        case .denied:
            currentLocation = nil
            status = .denied
            finishRequest(
                with: .failure(
                    TechnicianLocationError.permissionDenied
                )
            )

        case .restricted:
            currentLocation = nil
            status = .restricted
            finishRequest(
                with: .failure(
                    TechnicianLocationError.permissionRestricted
                )
            )

        case .notDetermined:
            status = pendingLocationCompletion == nil
                ? .notRequested
                : .requestingPermission

        @unknown default:
            currentLocation = nil
            status = .unavailable
            finishRequest(
                with: .failure(
                    TechnicianLocationError.locationUnavailable
                )
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
                with: .failure(
                    TechnicianLocationError.locationUnavailable
                )
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

        if let coreLocationError = error as? CLError {
            switch coreLocationError.code {
            case .denied:
                handleServicesOrPermissionDenied()

            case .locationUnknown:
                status = .unavailable
                finishRequest(
                    with: .failure(
                        TechnicianLocationError.locationUnavailable
                    )
                )

            default:
                status = .unavailable
                finishRequest(with: .failure(error))
            }
        } else {
            status = .unavailable
            finishRequest(with: .failure(error))
        }
    }

    // MARK: - Private

    private func performLocationAccessRequest() {
        switch authorizationStatus {
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

    private func performCurrentLocationRequest() {
        switch authorizationStatus {
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
                with: .failure(
                    TechnicianLocationError.permissionDenied
                )
            )

        case .restricted:
            status = .restricted
            finishRequest(
                with: .failure(
                    TechnicianLocationError.permissionRestricted
                )
            )

        @unknown default:
            status = .unavailable
            finishRequest(
                with: .failure(
                    TechnicianLocationError.locationUnavailable
                )
            )
        }
    }

    private func checkLocationServices(
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let servicesEnabled =
                CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async {
                completion(servicesEnabled)
            }
        }
    }

    private func handleServicesDisabled() {
        currentLocation = nil
        status = .servicesDisabled
        finishRequest(
            with: .failure(
                TechnicianLocationError.servicesDisabled
            )
        )
    }

    private func handleServicesOrPermissionDenied() {
        currentLocation = nil

        if authorizationStatus == .denied {
            status = .denied
            finishRequest(
                with: .failure(
                    TechnicianLocationError.permissionDenied
                )
            )
        } else {
            status = .servicesDisabled
            finishRequest(
                with: .failure(
                    TechnicianLocationError.servicesDisabled
                )
            )
        }
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
