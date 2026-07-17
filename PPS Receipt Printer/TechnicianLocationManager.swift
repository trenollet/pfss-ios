//
//  TechnicianLocationManager.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/17/26.
//

//
//  TechnicianLocationManager.swift
//  PPS Receipt Printer
//

import Foundation
import CoreLocation
import Combine

final class TechnicianLocationManager: NSObject,
                                       ObservableObject,
                                       CLLocationManagerDelegate {

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocation?
    @Published var locationError: Error?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus

        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Public

    func requestLocationAccess() {
        switch authorizationStatus {

        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways,
             .authorizedWhenInUse:
            manager.requestLocation()

        default:
            break
        }
    }

    func refreshLocation() {
        guard authorizationStatus == .authorizedAlways ||
              authorizationStatus == .authorizedWhenInUse
        else {
            return
        }

        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {

        case .authorizedAlways,
             .authorizedWhenInUse:
            manager.requestLocation()

        default:
            currentLocation = nil
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        currentLocation = locations.first
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        locationError = error
    }
}
