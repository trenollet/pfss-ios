//
//  PFSSJobStartReminderService.swift
//  PPS Receipt Printer
//
//  Field reminder scheduled after a technician marks a job Arrived.
//

import Foundation
import UIKit
import UserNotifications

final class PFSSJobStartReminderService: NSObject {
    static let shared = PFSSJobStartReminderService()

    static let categoryIdentifier = "PFSS_JOB_START_REMINDER"
    static let snoozeActionIdentifier = "PFSS_JOB_START_REMINDER_SNOOZE"
    static let openActionIdentifier = "PFSS_JOB_START_REMINDER_OPEN"

    private let center = UNUserNotificationCenter.current()
    private static let testFixtureJobNumbers: Set<String> = [
        "JOB-CROSS-ENTRY-POINT",
        "JOB-STEP-6-ACCEPTANCE",
    ]
    private enum ReminderKind: String {
        case startSetup
        case startWork
    }

    private override init() {
        super.init()
    }

    func registerNotificationCategory() {
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "Open PFSS",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Remind in 5 Minutes"
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [open, snooze],
                intentIdentifiers: []
            )
        ])
    }

    func scheduleAfterArrival(for job: JobRecord, minutes: Int) {
        scheduleReminder(for: job, kind: .startSetup, minutes: minutes)
    }

    func scheduleAfterSetup(for job: JobRecord, minutes: Int) {
        scheduleReminder(for: job, kind: .startWork, minutes: minutes)
    }

    private func scheduleReminder(
        for job: JobRecord,
        kind: ReminderKind,
        minutes: Int
    ) {
        guard ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath"
        ] == nil else { return }
        guard minutes > 0 else {
            cancel(for: job.id)
            return
        }
        Task {
            let settings = await center.notificationSettings()
            var isAuthorized = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral

            if settings.authorizationStatus == .notDetermined {
                isAuthorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )) == true
            }
            guard isAuthorized else { return }

            await schedule(
                jobID: job.id,
                jobNumber: job.jobNumber,
                kind: kind,
                after: TimeInterval(minutes * 60)
            )
        }
    }

    func cancel(for jobID: UUID) {
        let identifier = notificationIdentifier(for: jobID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Removes notifications created by historical physical-device test runs.
    /// Matching is deliberately limited to exact integration-test job markers
    /// so production reminders can never be removed by this repair.
    func removeLeakedTestFixtureNotifications() {
        Task {
            let pending = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            let identifiers = Set(
                pending.compactMap { request in
                    Self.isTestFixtureNotification(request)
                        ? request.identifier
                        : nil
                } + delivered.compactMap { notification in
                    Self.isTestFixtureNotification(notification.request)
                        ? notification.request.identifier
                        : nil
                }
            )
            guard !identifiers.isEmpty else { return }
            let values = Array(identifiers)
            center.removePendingNotificationRequests(withIdentifiers: values)
            center.removeDeliveredNotifications(withIdentifiers: values)
        }
    }

    static func isTestFixtureJobNumber(_ jobNumber: String) -> Bool {
        jobNumber.hasPrefix("JOB-OFFLINE-") ||
            jobNumber.hasPrefix("JOB-FIELD-DAY-") ||
            testFixtureJobNumbers.contains(jobNumber)
    }

    private static func isTestFixtureNotification(
        _ request: UNNotificationRequest
    ) -> Bool {
        guard request.content.categoryIdentifier == categoryIdentifier,
              let jobNumber = request.content.userInfo["jobNumber"] as? String
        else { return false }
        return isTestFixtureJobNumber(jobNumber)
    }

    func snooze(from response: UNNotificationResponse) async {
        guard let jobIDValue = response.notification.request.content
            .userInfo["jobID"] as? String,
              let jobID = UUID(uuidString: jobIDValue),
              let jobNumber = response.notification.request.content
                .userInfo["jobNumber"] as? String,
              let kindValue = response.notification.request.content
                .userInfo["reminderKind"] as? String,
              let kind = ReminderKind(rawValue: kindValue) else { return }
        await schedule(
            jobID: jobID,
            jobNumber: jobNumber,
            kind: kind,
            after: 5 * 60
        )
    }

    private func schedule(
        jobID: UUID,
        jobNumber: String,
        kind: ReminderKind,
        after delay: TimeInterval
    ) async {
        cancel(for: jobID)

        let content = UNMutableNotificationContent()
        switch kind {
        case .startSetup:
            content.title = "Start the Setup Timer"
            content.body = "You arrived for \(jobNumber), but setup has not started."
        case .startWork:
            content.title = "Start the Work Timer"
            content.body = "Setup began for \(jobNumber), but work has not started."
        }
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "pfss-job-workflow"
        content.userInfo = [
            "jobID": jobID.uuidString,
            "jobNumber": jobNumber,
            "reminderKind": kind.rawValue
        ]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: jobID),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: delay,
                repeats: false
            )
        )
        try? await center.add(request)
    }

    private func notificationIdentifier(for jobID: UUID) -> String {
        "pfss-job-start-reminder-\(jobID.uuidString.lowercased())"
    }
}

final class PFSSApplicationDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        PFSSJobStartReminderService.shared.registerNotificationCategory()
        PFSSJobStartReminderService.shared
            .removeLeakedTestFixtureNotifications()
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PFSSSynchronizationPushBridge.store(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Periodic and foreground reconciliation remain authoritative fallback.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler:
            @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard userInfo["pfss"] as? String == "syncWake" else {
            completionHandler(.noData)
            return
        }
        PFSSSynchronizationPushBridge.markWakePending(
            deliveryID: userInfo["deliveryID"] as? String,
            expectedCursor: (userInfo["cursor"] as? NSNumber)?.intValue,
            completionHandler: completionHandler
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier ==
            PFSSJobStartReminderService.snoozeActionIdentifier {
            await PFSSJobStartReminderService.shared.snooze(from: response)
        }
    }
}

@MainActor
enum PFSSSynchronizationPushBridge {
    private static let tokenKey = "pfss.synchronization.push.token"
    private static let pendingWakeKey = "pfss.synchronization.push.pendingWake"
    private static let pendingDeliveryKey =
        "pfss.synchronization.push.pendingDelivery"
    private static let pendingCursorKey =
        "pfss.synchronization.push.pendingCursor"
    private static var completionHandlers:
        [UUID: (UIBackgroundFetchResult) -> Void] = [:]

    static var currentToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func store(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        NotificationCenter.default.post(
            name: .pfssSynchronizationPushTokenDidChange,
            object: token
        )
    }

    static func markWakePending(
        deliveryID: String?,
        expectedCursor: Int?,
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let wakeID = UUID()
        completionHandlers[wakeID] = completionHandler
        UserDefaults.standard.set(wakeID.uuidString, forKey: pendingWakeKey)
        UserDefaults.standard.set(deliveryID, forKey: pendingDeliveryKey)
        if let expectedCursor {
            UserDefaults.standard.set(expectedCursor, forKey: pendingCursorKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingCursorKey)
        }
        let wake = PFSSSynchronizationWakeRequest(
            wakeID: wakeID,
            deliveryID: deliveryID,
            expectedCursor: expectedCursor
        )
        NotificationCenter.default.post(
            name: .pfssSynchronizationWakeRequested,
            object: wake
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            completeWake(wakeID, result: .failed)
        }
    }

    static func consumePendingWake() -> PFSSSynchronizationWakeRequest? {
        guard let value = UserDefaults.standard.string(forKey: pendingWakeKey),
              let wakeID = UUID(uuidString: value) else {
            return nil
        }
        let defaults = UserDefaults.standard
        return PFSSSynchronizationWakeRequest(
            wakeID: wakeID,
            deliveryID: defaults.string(forKey: pendingDeliveryKey),
            expectedCursor: defaults.object(forKey: pendingCursorKey) == nil
                ? nil
                : defaults.integer(forKey: pendingCursorKey)
        )
    }

    static func completeWake(
        _ wakeID: UUID,
        result: UIBackgroundFetchResult
    ) {
        if UserDefaults.standard.string(forKey: pendingWakeKey) ==
            wakeID.uuidString {
            UserDefaults.standard.removeObject(forKey: pendingWakeKey)
            UserDefaults.standard.removeObject(forKey: pendingDeliveryKey)
            UserDefaults.standard.removeObject(forKey: pendingCursorKey)
        }
        completionHandlers.removeValue(forKey: wakeID)?(result)
    }
}

struct PFSSSynchronizationWakeRequest: Sendable {
    let wakeID: UUID
    let deliveryID: String?
    let expectedCursor: Int?
}
