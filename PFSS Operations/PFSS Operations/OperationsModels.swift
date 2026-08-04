import Foundation

struct OperationsAdministrator: Codable, Equatable {
    let id: String
    let displayName: String
    let email: String
    let role: String
}

struct OperationsSessionReceipt: Codable {
    struct Device: Codable {
        let id: String
        let displayName: String
    }

    let administrator: OperationsAdministrator
    let device: Device
    let expiresAt: Date
}

struct OperationsAuthorizationSession: Codable {
    let authorizationURL: URL
    let state: String
    let expiresAt: Date
}

struct OperationsSignInReceipt: Codable {
    let sessionToken: String
    let expiresAt: Date
    let administrator: OperationsAdministrator
}

struct OperationsSummary: Codable {
    struct Accounts: Codable { let total: Int }
    struct Users: Codable { let active: Int }
    struct Devices: Codable {
        let active: Int
        let pendingDataRemoval: Int
    }
    struct Errors: Codable {
        let unresolvedSynchronizationConflicts: Int
        let failedRegistrations: Int
    }

    let accounts: Accounts
    let users: Users
    let devices: Devices
    let errors: Errors
    let generatedAt: Date
}

struct OperationsMonitoring: Codable {
    struct ProviderMetric: Codable, Identifiable {
        let provider: String
        let name: String
        let used: Double?
        let limit: Double?
        let unit: String
        let source: String
        let utilization: Double?
        let status: String
        var id: String { "\(provider)-\(name)" }
    }

    struct AccountAlert: Codable, Identifiable {
        let tenantID: String
        let accountName: String
        let resource: String
        let used: Int
        let limit: Int
        let utilization: Double
        let severity: String
        var id: String { "\(tenantID)-\(resource)" }
    }

    struct ErrorItem: Codable, Identifiable {
        let id: String
        let tenantID: String?
        let accountName: String?
        let category: String
        let severity: String
        let summary: String
        let occurredAt: Date
        let email: String?
        let entityType: String?
        let deviceName: String?
    }

    let providerMetrics: [ProviderMetric]
    let accountAlerts: [AccountAlert]
    let errors: [ErrorItem]
    let archiveObjects: Int
    let generatedAt: Date
}

struct OperationsAccount: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let createdAt: Date
    let lifecycleStatus: String
    let subscriptionStatus: String?
    let planCode: String?
    let accessSource: String?
    let activeUsers: Int
    let activeDevices: Int
    let lastActivityAt: Date?
}

struct OperationsAccountsPage: Codable {
    struct Page: Codable {
        let offset: Int
        let limit: Int
        let hasMore: Bool
        let nextOffset: Int?
    }

    let accounts: [OperationsAccount]
    let page: Page
}

struct OperationsAccountDetail: Codable {
    struct Account: Codable {
        let id: String
        let displayName: String
        let createdAt: Date
        let lifecycleStatus: String
        let lifecycleReason: String?
        let holdExpiresAt: Date?
        let archivedAt: Date?
        let deletionScheduledAt: Date?
        let subscriptionStatus: String?
        let planCode: String?
        let accessSource: String?
        let entitlements: Entitlements
        let planEffectiveAt: Date?
        let planExpiresAt: Date?
        let overrideReason: String?
    }

    struct Entitlements: Codable {
        let userLimit: Int?
        let deviceLimit: Int?
        let leadLimit: Int?
        let customerLimit: Int?
        let jobLimit: Int?
    }

    struct Member: Codable, Identifiable {
        let id: String
        let displayName: String
        let email: String?
        let role: String
        let status: String
        let employeeID: String?
        let recoveryAvailable: Int
        let createdAt: Date
        let activatedAt: Date?
        let revokedAt: Date?
        let archivedAt: Date?
        let removedAt: Date?
    }

    struct Device: Codable, Identifiable {
        let id: String
        let memberID: String
        let displayName: String
        let memberName: String
        let memberEmail: String?
        let status: String
        let createdAt: Date
        let lastSeenAt: Date
        let revokedAt: Date?
        let dataRemovalRequiredAt: Date?
        let dataRemovalAcknowledgedAt: Date?
        let removedAt: Date?
    }

    struct Usage: Codable, Identifiable {
        let entityType: String
        let count: Int
        var id: String { entityType }
    }

    struct Errors: Codable {
        let unresolvedSynchronizationConflicts: Int
    }

    struct AuditEvent: Codable, Identifiable {
        let eventType: String
        let createdAt: Date
        let metadata: [String: String]
        var id: String { "\(createdAt.timeIntervalSince1970)-\(eventType)" }
    }

    let account: Account
    let members: [Member]
    let devices: [Device]
    let usage: [Usage]
    let errors: Errors
    let recentAudit: [AuditEvent]
}

struct OperationsRecoveryReceipt: Codable {
    let status: String
    let email: String?
    let workOSSessions: Int?
    let pfssDevices: Int?
    let effectiveAt: Date
}

struct OperationsAccessLifecycleReceipt: Codable {
    let memberID: String?
    let deviceID: String?
    let status: String
    let effectiveAt: Date
}

struct OperationsLifecycleReceipt: Codable {
    let status: String
    let reason: String
    let holdExpiresAt: Date?
    let effectiveAt: Date
    let deletionScheduledAt: Date?
}

struct OperationsDeletionReadiness: Codable {
    struct PendingDevice: Codable, Identifiable {
        let id: String
        let displayName: String
        let memberName: String
        let lastSeenAt: Date
    }

    let ready: Bool
    let pendingDevices: [PendingDevice]
    let latestBackupAt: Date?
    let synchronizationSnapshotAvailable: Bool
}

struct OperationsReadinessActionReceipt: Codable {
    let status: String
    let confirmedAt: Date?
    let confirmedDevices: Int?
    let archiveID: String?
    let uploadedAt: Date?
}

struct OperationsPlanOverrideReceipt: Codable {
    let id: String
    let planCode: String
    let accessSource: String
    let entitlements: OperationsAccountDetail.Entitlements
    let effectiveAt: Date
    let expiresAt: Date?
    let reason: String
}
