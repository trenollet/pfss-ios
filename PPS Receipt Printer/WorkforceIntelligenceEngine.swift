//
//  WorkforceIntelligenceEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.5 — Workforce Intelligence
//

import Foundation

/// Read-only operational intelligence for employees.
///
/// This engine does not assign, rank, dispatch, or modify technicians. It
/// converts employee profiles and live Assignment data into consistent,
/// explainable evidence for Scheduling, Daily Planner, Dispatch, and the
/// Step 6 Recommendation Engine.
@MainActor
final class WorkforceIntelligenceEngine {
    private let calendar: Calendar
    private let certificationWarningDays: Int

    init(
        calendar: Calendar = .current,
        certificationWarningDays: Int = 30
    ) {
        self.calendar = calendar
        self.certificationWarningDays = max(certificationWarningDays, 0)
    }

    // MARK: - Unified Snapshot

    func snapshot(
        for employee: EmployeeRecord,
        on date: Date,
        assignments: [Assignment]
    ) -> WorkforceTechnicianSnapshot {
        snapshot(
            for: employee,
            on: date,
            assignments: assignments,
            requirements: WorkforceCapabilityRequirements()
        )
    }

    func snapshot(
        for employee: EmployeeRecord,
        on date: Date,
        assignments: [Assignment],
        requirements: WorkforceCapabilityRequirements
    ) -> WorkforceTechnicianSnapshot {
        WorkforceTechnicianSnapshot(
            employeeID: employee.id,
            employeeName: employee.displayName,
            generatedAt: Date(),
            capability: evaluateCapability(
                of: employee,
                for: requirements,
                on: date
            ),
            availability: evaluateAvailability(
                of: employee,
                on: date
            ),
            workload: workload(
                for: employee,
                on: date,
                assignments: assignments
            ),
            history: historicalMetrics(
                for: employee,
                assignments: assignments
            )
        )
    }

    func snapshots(
        for employees: [EmployeeRecord],
        on date: Date,
        assignments: [Assignment]
    ) -> [WorkforceTechnicianSnapshot] {
        snapshots(
            for: employees,
            on: date,
            assignments: assignments,
            requirements: WorkforceCapabilityRequirements()
        )
    }

    func snapshots(
        for employees: [EmployeeRecord],
        on date: Date,
        assignments: [Assignment],
        requirements: WorkforceCapabilityRequirements
    ) -> [WorkforceTechnicianSnapshot] {
        employees
            .map {
                snapshot(
                    for: $0,
                    on: date,
                    assignments: assignments,
                    requirements: requirements
                )
            }
            .sorted {
                $0.employeeName.localizedCaseInsensitiveCompare(
                    $1.employeeName
                ) == .orderedAscending
            }
    }

    // MARK: - Capability

    func evaluateCapability(
        of employee: EmployeeRecord,
        for requirements: WorkforceCapabilityRequirements,
        on date: Date = Date()
    ) -> WorkforceCapabilityEvaluation {
        guard employee.isActive,
              employee.lifecycleStatus == .active else {
            return WorkforceCapabilityEvaluation(
                state: .notQualified,
                evidence: [
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .employee,
                        message: "Employee is inactive or archived."
                    )
                ]
            )
        }

        guard !requirements.isEmpty else {
            return WorkforceCapabilityEvaluation(
                state: .qualified,
                evidence: [
                    WorkforceEvidence(
                        severity: .information,
                        category: .skill,
                        message: "No special workforce requirements were specified."
                    )
                ]
            )
        }

        let profile = employee.workforceProfile
        var evidence: [WorkforceEvidence] = []

        if let serviceType = requirements.requiredServiceType {
            let matchingSkills = profile.skills.filter {
                $0.isValid && $0.serviceType == serviceType
            }

            if let best = matchingSkills.max(by: {
                $0.proficiency < $1.proficiency
            }), best.proficiency >= requirements.minimumProficiency {
                evidence.append(
                    WorkforceEvidence(
                        severity: .satisfied,
                        category: .skill,
                        message: "\(serviceType.rawValue): \(best.proficiency.displayName)."
                    )
                )
            } else if matchingSkills.isEmpty {
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .skill,
                        message: "No \(serviceType.rawValue) skill is recorded."
                    )
                )
            } else {
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .skill,
                        message: "\(serviceType.rawValue) proficiency is below \(requirements.minimumProficiency.displayName)."
                    )
                )
            }
        }

        for requiredName in normalizedUnique(
            requirements.requiredSkillNames
        ) {
            let matches = profile.skills.filter {
                $0.isValid && $0.normalizedName == requiredName
            }

            if let best = matches.max(by: {
                $0.proficiency < $1.proficiency
            }), best.proficiency >= requirements.minimumProficiency {
                evidence.append(
                    WorkforceEvidence(
                        severity: .satisfied,
                        category: .skill,
                        message: "Skill available: \(best.name) (\(best.proficiency.displayName))."
                    )
                )
            } else if matches.isEmpty {
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .skill,
                        message: "Required skill is missing: \(requiredName.capitalized)."
                    )
                )
            } else {
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .skill,
                        message: "\(matches[0].name) is below \(requirements.minimumProficiency.displayName)."
                    )
                )
            }
        }

        for requiredName in normalizedUnique(
            requirements.requiredCertificationNames
        ) {
            let matches = profile.certifications.filter {
                $0.normalizedName == requiredName
            }

            guard let certification = matches.first else {
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .certification,
                        message: "Required certification is missing: \(requiredName.capitalized)."
                    )
                )
                continue
            }

            switch certification.status(
                on: date,
                warningDays: certificationWarningDays,
                calendar: calendar
            ) {
            case .active:
                evidence.append(
                    WorkforceEvidence(
                        severity: .satisfied,
                        category: .certification,
                        message: "Certification active: \(certification.name)."
                    )
                )

            case .expiresSoon:
                evidence.append(
                    WorkforceEvidence(
                        severity: .warning,
                        category: .certification,
                        message: "\(certification.name) expires soon."
                    )
                )

            case .expired:
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .certification,
                        message: "\(certification.name) is expired."
                    )
                )

            case .inactive:
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .certification,
                        message: "\(certification.name) is inactive."
                    )
                )
            }
        }

        for requiredName in normalizedUnique(
            requirements.requiredResourceNames
        ) {
            if let resource = profile.resourceAccess.first(where: {
                $0.normalizedName == requiredName && $0.isAvailable
            }) {
                evidence.append(
                    WorkforceEvidence(
                        severity: .satisfied,
                        category: .resource,
                        message: "Resource available: \(resource.name)."
                    )
                )
            } else {
                evidence.append(
                    WorkforceEvidence(
                        severity: .blocking,
                        category: .resource,
                        message: "Required resource is unavailable: \(requiredName.capitalized)."
                    )
                )
            }
        }

        if requirements.requiresVehicleAccess {
            let vehicle = profile.resourceAccess.first {
                $0.type == .vehicle && $0.isAvailable
            }

            evidence.append(
                WorkforceEvidence(
                    severity: vehicle == nil ? .blocking : .satisfied,
                    category: .resource,
                    message: vehicle.map {
                        "Vehicle access available: \($0.name)."
                    } ?? "Vehicle access is required but not recorded."
                )
            )
        }

        let state: WorkforceCapabilityState
        if evidence.contains(where: { $0.severity == .blocking }) {
            state = .notQualified
        } else if evidence.contains(where: { $0.severity == .warning }) {
            state = .qualifiedWithWarnings
        } else {
            state = .qualified
        }

        return WorkforceCapabilityEvaluation(
            state: state,
            evidence: evidence
        )
    }

    // MARK: - Availability

    func evaluateAvailability(
        of employee: EmployeeRecord,
        on date: Date
    ) -> WorkforceAvailabilityEvaluation {
        guard employee.isActive,
              employee.lifecycleStatus == .active else {
            return WorkforceAvailabilityEvaluation(
                state: .inactive,
                availableInterval: nil,
                reason: "Employee is inactive or archived."
            )
        }

        let dayInterval = intervalForDay(containing: date)
        let exceptions = employee.workforceProfile.availabilityExceptions
            .filter { $0.overlaps(dayInterval) }
            .sorted { $0.startDate < $1.startDate }

        if let unavailable = exceptions.first(where: {
            $0.kind == .unavailable
        }) {
            return WorkforceAvailabilityEvaluation(
                state: .unavailable,
                availableInterval: nil,
                reason: unavailable.reason.isEmpty
                    ? "Unavailable by workforce exception."
                    : unavailable.reason
            )
        }

        if let limited = exceptions.first(where: {
            $0.kind == .limited
        }) {
            let interval = clampedInterval(
                start: limited.startDate,
                end: limited.endDate,
                within: dayInterval
            )
            return WorkforceAvailabilityEvaluation(
                state: .limited,
                availableInterval: interval,
                reason: limited.reason.isEmpty
                    ? "Limited availability."
                    : limited.reason
            )
        }

        if let override = exceptions.first(where: {
            $0.kind == .available
        }) {
            return WorkforceAvailabilityEvaluation(
                state: .availableOverride,
                availableInterval: clampedInterval(
                    start: override.startDate,
                    end: override.endDate,
                    within: dayInterval
                ),
                reason: override.reason.isEmpty
                    ? "Available by workforce override."
                    : override.reason
            )
        }

        guard let workday = Workday(
            rawValue: calendar.component(.weekday, from: date)
        ), employee.workingDays.contains(workday) else {
            return WorkforceAvailabilityEvaluation(
                state: .offSchedule,
                availableInterval: nil,
                reason: "Not normally scheduled to work this day."
            )
        }

        let start = dateOnDay(
            date,
            minutesAfterMidnight: employee.defaultStartMinutes
        )
        let end = dateOnDay(
            date,
            minutesAfterMidnight: employee.defaultEndMinutes
        )

        guard end > start else {
            return WorkforceAvailabilityEvaluation(
                state: .unavailable,
                availableInterval: nil,
                reason: "Employee work hours are invalid."
            )
        }

        return WorkforceAvailabilityEvaluation(
            state: .available,
            availableInterval: DateInterval(start: start, end: end),
            reason: "Available during the normal workday."
        )
    }

    // MARK: - Workload

    func workload(
        for employee: EmployeeRecord,
        on date: Date,
        assignments: [Assignment]
    ) -> WorkforceWorkloadSnapshot {
        let matchingAssignments = assignments
            .filter { assignment in
                guard assignment.lifecycleStatus == .active,
                      assignment.status.isActive,
                      assignment.crew.containsActiveEmployee(employee.id),
                      let operationalDate = assignment.scheduling.operationalDate else {
                    return false
                }

                return calendar.isDate(operationalDate, inSameDayAs: date)
            }
            .sorted {
                let lhsDate = $0.scheduling.operationalDate ?? .distantFuture
                let rhsDate = $1.scheduling.operationalDate ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return $0.assignmentNumber.localizedStandardCompare(
                    $1.assignmentNumber
                ) == .orderedAscending
            }

        let assignedMinutes = matchingAssignments.reduce(0) {
            $0 + $1.scheduling.totalPlannedMinutes
        }
        let capacity = max(employee.dailyCapacityMinutes, 0)
        let utilization = capacity > 0
            ? min(max(Double(assignedMinutes) / Double(capacity), 0), 1)
            : (assignedMinutes > 0 ? 1 : 0)
        let maximum = employee.workforceProfile.maximumDailyAssignments
        let exceedsMaximum = maximum.map {
            matchingAssignments.count > $0
        } ?? false

        return WorkforceWorkloadSnapshot(
            employeeID: employee.id,
            date: calendar.startOfDay(for: date),
            activeAssignmentIDs: matchingAssignments.map(\.id),
            assignmentCount: matchingAssignments.count,
            assignedMinutes: assignedMinutes,
            capacityMinutes: capacity,
            remainingCapacityMinutes: max(capacity - assignedMinutes, 0),
            utilizationFraction: utilization,
            exceedsMaximumDailyAssignments: exceedsMaximum
        )
    }

    // MARK: - History and Metrics

    func historicalMetrics(
        for employee: EmployeeRecord,
        assignments: [Assignment]
    ) -> WorkforceHistoricalMetrics {
        let completed = assignments.filter { assignment in
            assignment.crew.members.contains {
                $0.employeeID == employee.id
            } && (
                assignment.status == .workComplete ||
                assignment.status == .invoiceReady ||
                assignment.status == .closed
            )
        }

        let laborMinutes = completed.reduce(0) { total, assignment in
            total + assignment.crew.members
                .filter { $0.employeeID == employee.id }
                .reduce(0) { $0 + $1.laborMinutes }
        }
        let average = completed.isEmpty
            ? nil
            : Double(laborMinutes) / Double(completed.count)
        let lastDate = completed.compactMap {
            $0.workCompletedDate ?? $0.closedDate
        }.max()
        let existing = employee.workforceProfile.historicalMetrics

        return WorkforceHistoricalMetrics(
            completedAssignmentCount: completed.count,
            totalRecordedLaborMinutes: laborMinutes,
            averageAssignmentMinutes: average,
            onTimeArrivalRate: existing.onTimeArrivalRate,
            firstTimeCompletionRate: existing.firstTimeCompletionRate,
            averageCustomerRating: existing.averageCustomerRating,
            lastCompletedAssignmentDate: lastDate,
            calculatedDate: Date()
        )
    }

    // MARK: - Direct Queries

    func skill(
        named name: String,
        for employee: EmployeeRecord
    ) -> WorkforceSkill? {
        let normalized = normalize(name)
        return employee.workforceProfile.skills
            .filter { $0.normalizedName == normalized }
            .max { $0.proficiency < $1.proficiency }
    }

    func validCertification(
        named name: String,
        for employee: EmployeeRecord,
        on date: Date = Date()
    ) -> WorkforceCertification? {
        let normalized = normalize(name)
        return employee.workforceProfile.certifications.first {
            $0.normalizedName == normalized && $0.isValid(on: date)
        }
    }

    func availableResource(
        named name: String,
        for employee: EmployeeRecord
    ) -> WorkforceResourceAccess? {
        let normalized = normalize(name)
        return employee.workforceProfile.resourceAccess.first {
            $0.normalizedName == normalized && $0.isAvailable
        }
    }

    // MARK: - Helpers

    private func normalizedUnique(_ values: [String]) -> [String] {
        Array(Set(values.map(normalize).filter { !$0.isEmpty })).sorted()
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func intervalForDay(containing date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private func dateOnDay(
        _ date: Date,
        minutesAfterMidnight: Int
    ) -> Date {
        calendar.date(
            byAdding: .minute,
            value: max(minutesAfterMidnight, 0),
            to: calendar.startOfDay(for: date)
        ) ?? date
    }

    private func clampedInterval(
        start: Date,
        end: Date,
        within boundary: DateInterval
    ) -> DateInterval? {
        let clampedStart = max(start, boundary.start)
        let clampedEnd = min(end, boundary.end)
        guard clampedEnd > clampedStart else { return nil }
        return DateInterval(start: clampedStart, end: clampedEnd)
    }
}

// MARK: - Results

enum WorkforceCapabilityState: String, Codable, Hashable {
    case qualified = "Qualified"
    case qualifiedWithWarnings = "Qualified with Warnings"
    case notQualified = "Not Qualified"
}

enum WorkforceEvidenceSeverity: String, Codable, Hashable {
    case information = "Information"
    case satisfied = "Satisfied"
    case warning = "Warning"
    case blocking = "Blocking"
}

enum WorkforceEvidenceCategory: String, Codable, Hashable {
    case employee = "Employee"
    case skill = "Skill"
    case certification = "Certification"
    case resource = "Resource"
    case availability = "Availability"
    case workload = "Workload"
}

struct WorkforceEvidence: Codable, Hashable {
    var severity: WorkforceEvidenceSeverity
    var category: WorkforceEvidenceCategory
    var message: String
}

struct WorkforceCapabilityEvaluation: Codable, Hashable {
    var state: WorkforceCapabilityState
    var evidence: [WorkforceEvidence]

    var meetsRequirements: Bool {
        state != .notQualified
    }

    var warnings: [WorkforceEvidence] {
        evidence.filter { $0.severity == .warning }
    }

    var blockers: [WorkforceEvidence] {
        evidence.filter { $0.severity == .blocking }
    }
}

enum WorkforceAvailabilityState: String, Codable, Hashable {
    case available = "Available"
    case availableOverride = "Available Override"
    case limited = "Limited"
    case unavailable = "Unavailable"
    case offSchedule = "Off Schedule"
    case inactive = "Inactive"

    var isAvailable: Bool {
        switch self {
        case .available, .availableOverride, .limited:
            return true
        case .unavailable, .offSchedule, .inactive:
            return false
        }
    }
}

struct WorkforceAvailabilityEvaluation: Codable, Hashable {
    var state: WorkforceAvailabilityState
    var availableInterval: DateInterval?
    var reason: String
}

struct WorkforceWorkloadSnapshot: Codable, Hashable {
    var employeeID: UUID
    var date: Date
    var activeAssignmentIDs: [UUID]
    var assignmentCount: Int
    var assignedMinutes: Int
    var capacityMinutes: Int
    var remainingCapacityMinutes: Int
    var utilizationFraction: Double
    var exceedsMaximumDailyAssignments: Bool

    var utilizationPercentage: Int {
        Int((min(max(utilizationFraction, 0), 1) * 100).rounded())
    }
}

struct WorkforceTechnicianSnapshot: Identifiable, Codable, Hashable {
    var employeeID: UUID
    var employeeName: String
    var generatedAt: Date
    var capability: WorkforceCapabilityEvaluation
    var availability: WorkforceAvailabilityEvaluation
    var workload: WorkforceWorkloadSnapshot
    var history: WorkforceHistoricalMetrics

    var id: UUID { employeeID }

    var isOperationallyEligible: Bool {
        capability.meetsRequirements && availability.state.isAvailable
    }
}
