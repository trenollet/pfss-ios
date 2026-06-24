//
//  models.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation

enum ServiceType: String, CaseIterable, Identifiable {
    case windowCleaning = "Window Cleaning"
    case pressureWashing = "Pressure Washing"
    case gutterCleaning = "Gutter Cleaning"
    case handymanServices = "Handyman Services"
    case other = "Other"

    var id: String { rawValue }
}

enum LeadSource: String, CaseIterable, Identifiable {
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

enum EstimateStatus: String, CaseIterable, Identifiable {
    case newLead = "New Lead"
    case estimateGiven = "Estimate Given"
    case followUpRequired = "Follow Up Required"
    case approved = "Approved"
    case rejected = "Rejected"
    case jobScheduled = "Job Scheduled"
    case completed = "Completed"

    var id: String { rawValue }
}

enum DocumentType: String, CaseIterable, Identifiable {
    case estimate = "Estimate"
    case invoice = "Invoice"
    case receipt = "Receipt"

    var id: String { rawValue }
}

enum PaymentStatus: String, CaseIterable, Identifiable {
    case unpaid = "Unpaid"
    case paid = "Paid"
    case depositPaid = "Deposit Paid"

    var id: String { rawValue }
}

struct Customer: Identifiable {
    let id = UUID()
    var customerNumber: String
    var businessName: String
    var contactName: String
    var phone: String
    var email: String
    var leadSource: LeadSource
    var estimateStatus: EstimateStatus
    var assignedEmployee: String
    var followUpDate: Date
}

struct CustomerSite: Identifiable {
    let id = UUID()
    var customerNumber: String
    var siteName: String
    var serviceAddress: String
    var propertyType: String
    var accessNotes: String
    var workNotes: String
}
