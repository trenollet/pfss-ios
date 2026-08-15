//
//  MileageLocationCoordinator.swift
//  PPS Receipt Printer
//
//  Phase 19 – Opt-in, battery-aware background mileage coordination.
//

import Combine
import CoreLocation
import CoreMotion
import CryptoKit
import Foundation
import UIKit
import UserNotifications

enum MileageMonitoringStatus: Equatable {
    case permissionRequired
    case monitoring
    case tracking
    case paused
    case locationUnavailable

    var title: String {
        switch self {
        case .permissionRequired: return "Permission Required"
        case .monitoring: return "Monitoring"
        case .tracking: return "Tracking"
        case .paused: return "Paused"
        case .locationUnavailable: return "Location Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .permissionRequired: return "location.slash"
        case .monitoring: return "location.circle"
        case .tracking: return "location.fill"
        case .paused: return "pause.circle"
        case .locationUnavailable: return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class MileageLocationCoordinator: NSObject, ObservableObject,
    CLLocationManagerDelegate {
    static let shared = MileageLocationCoordinator()

    @Published private(set) var status: MileageMonitoringStatus = .paused
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastErrorMessage = ""
    @Published private(set) var isConfigured = false
    @Published var isAutomaticTrackingEnabled: Bool {
        didSet {
            defaults.set(isAutomaticTrackingEnabled, forKey: enabledKey)
            applyMonitoringMode()
        }
    }

    let repository: MileageTripRepository

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PFSS Mileage Motion"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let enabledKey = "PFSSAutomaticMileageTrackingEnabled"
    private var context: MileageTrackingContext?
    private var engine: MileageDetectionEngine?
    private var isAutomotiveActivity = false

    init(
        repository: MileageTripRepository? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository ?? .shared
        self.defaults = defaults
        authorizationStatus = locationManager.authorizationStatus
        isAutomaticTrackingEnabled = defaults.bool(forKey: enabledKey)
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    func configureFromCurrentSession() async {
        let manager = PFSSCloudflareBetaManager()
        guard manager.isEnrolled else {
            suspendForLogout()
            return
        }
        do {
            try await manager.refreshSession()
            guard let session = manager.currentSession,
                  let context = Self.context(
                    from: session,
                    fallbackDeviceID: manager.registrationDeviceID()
                  ) else {
                status = .locationUnavailable
                lastErrorMessage = "PFSS could not identify the signed-in user for mileage tracking."
                return
            }
            try configure(context: context)
        } catch {
            status = .locationUnavailable
            lastErrorMessage = error.localizedDescription
        }
    }

    func configure(context: MileageTrackingContext) throws {
        try repository.configure(context: context)
        self.context = context
        engine = repository.restoredEngine() ?? MileageDetectionEngine(
            context: context
        )
        isConfigured = true
        lastErrorMessage = ""
        applyMonitoringMode()
    }

    func enableAutomaticTracking() {
        isAutomaticTrackingEnabled = true
        requestNotificationPermission()
        requestRequiredLocationPermission()
    }

    func disableAutomaticTracking() {
        isAutomaticTrackingEnabled = false
    }

    func requestRequiredLocationPermission() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .locationUnavailable
            lastErrorMessage = "Location Services are turned off on this device."
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            applyMonitoringMode()
        case .denied, .restricted:
            status = .permissionRequired
        @unknown default:
            status = .locationUnavailable
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    func suspendForLogout() {
        stopAllMonitoring()
        context = nil
        engine = nil
        isConfigured = false
        status = .paused
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        authorizationStatus = manager.authorizationStatus
        if isAutomaticTrackingEnabled,
           manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
            status = .permissionRequired
            return
        }
        applyMonitoringMode()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard isAutomaticTrackingEnabled, isConfigured else { return }
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.timestamp.timeIntervalSinceNow > -120 else {
                continue
            }
            let speed = max(0, location.speed)
            let point = MileageTripPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                speedMetersPerSecond: speed
            )
            process(point)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        lastErrorMessage = error.localizedDescription
        status = .locationUnavailable
    }

    private func process(_ point: MileageTripPoint) {
        guard var engine else { return }
        let events = engine.process(point)
        self.engine = engine
        do {
            try repository.checkpoint(
                engine: engine.state == .idle ? nil : engine
            )
            for event in events {
                handle(event)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            status = .locationUnavailable
        }
    }

    private func handle(_ event: MileageDetectionEvent) {
        switch event {
        case let .stateChanged(state):
            switch state {
            case .tracking, .stopping:
                status = .tracking
                enterRouteQualityMode()
            case .idle, .arming:
                status = .monitoring
            }
        case .tripStarted:
            status = .tracking
            notify(
                title: "Mileage Tracking Started",
                body: "PFSS detected a drive and is recording the route."
            )
        case let .tripCompleted(trip):
            do {
                try repository.save(trip)
                status = .monitoring
                enterLowPowerMode()
                notify(
                    title: "Trip Ready to Review",
                    body: String(
                        format: "Classify your %.1f mile trip as Business or Personal.",
                        trip.distanceMiles
                    )
                )
            } catch {
                lastErrorMessage = error.localizedDescription
                status = .locationUnavailable
            }
        }
    }

    private func applyMonitoringMode() {
        guard isConfigured, isAutomaticTrackingEnabled else {
            stopAllMonitoring()
            status = .paused
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            stopAllMonitoring()
            status = .locationUnavailable
            return
        }
        guard locationManager.authorizationStatus == .authorizedAlways else {
            stopAllMonitoring()
            status = .permissionRequired
            return
        }
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        startMotionMonitoring()
        if engine?.state == .tracking || engine?.state == .stopping {
            enterRouteQualityMode()
            status = .tracking
        } else {
            enterLowPowerMode()
            status = .monitoring
        }
    }

    private func enterLowPowerMode() {
        locationManager.stopUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 30.48
        locationManager.startMonitoringSignificantLocationChanges()
    }

    private func enterRouteQualityMode() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.startUpdatingLocation()
    }

    private func startMotionMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let becameAutomotive = activity.automotive &&
                    activity.confidence != .low
                guard becameAutomotive != self.isAutomotiveActivity else {
                    return
                }
                self.isAutomotiveActivity = becameAutomotive
                if becameAutomotive,
                   self.status == .monitoring {
                    self.locationManager.desiredAccuracy =
                        kCLLocationAccuracyNearestTenMeters
                    self.locationManager.distanceFilter = 15
                    self.locationManager.startUpdatingLocation()
                } else if !becameAutomotive,
                          self.engine?.state == .idle {
                    self.enterLowPowerMode()
                }
            }
        }
    }

    private func stopAllMonitoring() {
        motionManager.stopActivityUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.allowsBackgroundLocationUpdates = false
        isAutomotiveActivity = false
    }

    private func requestNotificationPermission() {
        Task {
            _ = try? await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "pfss-mileage"
        let request = UNNotificationRequest(
            identifier: "pfss-mileage-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    private static func context(
        from session: PFSSCloudflareSession,
        fallbackDeviceID: UUID
    ) -> MileageTrackingContext? {
        let userValue = session.member.employeeID ?? session.member.id
        let accountValue = session.tenant.id ?? session.tenant.displayName
        return MileageTrackingContext(
            accountID: UUID(uuidString: accountValue) ?? stableUUID(accountValue),
            userID: UUID(uuidString: userValue) ?? stableUUID(userValue),
            deviceID: UUID(uuidString: session.device.id) ?? fallbackDeviceID
        )
    }

    private static func stableUUID(_ value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
