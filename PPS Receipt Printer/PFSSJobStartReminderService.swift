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
        return true
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
