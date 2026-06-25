//
//  models.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation

enum ServiceType: String, CaseIterable, Identifiable, Codable {
    case windowCleaning = "Window Cleaning"
    case pressureWashing = "Pressure Washing"
    case gutterCleaning = "Gutter Cleaning"
    case handymanServices = "Handyman Services"
    case other = "Other"

    var id: String { rawValue }
}

enum LeadSource: String, CaseIterable, Identifiable, Codable {
    case website = "Website"
    case phoneCall = "Phone Call"
    case socialMedia = "Social Media"
    case google = "Google"
    case referral = "Referral"
    case doorKnock = "Door Knock"
    case repeatCustomer = "Repeat Customer"
    case other = "Other"

    var id: String { rawValue }
}

enum EstimateStatus: String, CaseIterable, Identifiable, Codable {
    case newLead = "New Lead"
    case estimateGiven = "Estimate Given"
    case followUpRequired = "Follow Up Required"
    case approved = "Approved"
    case rejected = "Rejected"
    case jobScheduled = "Job Scheduled"
    case completed = "Completed"

    var id: String { rawValue }
}
enum EstimateRecordStatus: String, CaseIterable, Identifiable, Codable {
    case draft = "Draft"
    case sent = "Sent"
    case approved = "Approved"
    case rejected = "Rejected"
    case expired = "Expired"
    case converted = "Converted"

    var id: String { rawValue }
}
enum DocumentType: String, CaseIterable, Identifiable, Codable {
    case estimate = "Estimate"
    case invoice = "Invoice"
    case receipt = "Receipt"

    var id: String { rawValue }
}
enum LeadStatus: String, CaseIterable, Identifiable, Codable {
    case newLead = "New Lead"
    case estimateScheduled = "Estimate Scheduled"
    case estimateGiven = "Estimate Given"
    case followUpRequired = "Follow Up Required"
    case approved = "Approved"
    case rejected = "Rejected"
    case converted = "Converted"

    var id: String { rawValue }
}
enum PaymentStatus: String, CaseIterable, Identifiable, Codable {
    case unpaid = "Unpaid"
    case paid = "Paid"
    case depositPaid = "Deposit Paid"

    var id: String { rawValue }
}

enum RecordLifecycleStatus: String, CaseIterable, Identifiable, Codable {
    case active = "Active"
    case archived = "Archived"

    var id: String { rawValue }
}
enum JobStatus: String, CaseIterable, Identifiable, Codable {
    case toBeScheduled = "To Be Scheduled"
    case scheduled = "Scheduled"
    case assigned = "Assigned"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var id: String { rawValue }
}

struct Customer: Identifiable, Codable {
    var id = UUID()
    var customerNumber: String
    var businessName: String
    var contactName: String
    var phone: String
    var email: String
    var leadSource: LeadSource
    var estimateStatus: EstimateStatus
    var assignedEmployee: String
    var followUpDate: Date
    var lifecycleStatus: RecordLifecycleStatus = .active
}

struct Lead: Identifiable, Codable {
    var id = UUID()
    var leadNumber: String
    var businessName: String
    var contactName: String
    var phone: String
    var email: String
    var leadSource: LeadSource
    var serviceRequested: ServiceType
    var otherService: String
    var estimatedValue: Double
    var assignedSalesperson: String
    var status: LeadStatus
    var followUpDate: Date
    var createdDate: Date
    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct EstimateRecord: Identifiable, Codable {
    var id = UUID()
    var estimateNumber: String
    var leadNumber: String
    var customerNumber: String
    var siteID: UUID?
    var serviceType: ServiceType
    var otherService: String
    var serviceDetails: String
    var subtotal: Double
    var discount: Double
    var total: Double
    var salesperson: String
    var status: EstimateRecordStatus
    var createdDate: Date
    var expirationDate: Date
    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct CustomerSite: Identifiable, Codable {
    var id = UUID()
    var customerNumber: String
    var siteName: String
    var serviceAddress: String
    var propertyType: String
    var accessNotes: String
    var workNotes: String
    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct JobRecord: Identifiable, Codable {
    var id = UUID()
    var jobNumber: String

    var customerNumber: String
    var siteID: UUID?
    var estimateNumber: String

    var serviceType: ServiceType
    var otherService: String

    var primaryTechnician: String
    var secondaryTechnician: String

    var scheduledDate: Date
    var completedDate: Date?

    var status: JobStatus
    var workNotes: String

    var isRecurring: Bool
    var createdDate: Date

    var lifecycleStatus: RecordLifecycleStatus = .active
}
