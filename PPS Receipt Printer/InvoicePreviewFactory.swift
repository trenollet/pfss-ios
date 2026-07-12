//
//  InvoicePreviewFactory.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import Foundation

struct InvoicePreviewFactory {
    static func sampleCustomer() -> Customer {
        Customer(
            customerNumber: "DEMO-000001",
            businessName: "Sample Customer",
            contactName: "Jordan Smith",
            phone: "(405) 555-0199",
            email: "customer@example.com",
            leadSource: .website,
            estimateStatus: .approved,
            assignedEmployee: "Demo User",
            followUpDate: Date()
        )
    }

    static func sampleSite(
        customerNumber: String
    ) -> CustomerSite {
        CustomerSite(
            customerNumber: customerNumber,
            siteName: "Main Property",
            serviceAddress: "123 Sample Street, Oklahoma City, OK 73102",
            propertyType: "Residential",
            accessNotes: "",
            workNotes: ""
        )
    }

    static func sampleCatalogItems() -> [ServiceCatalogItem] {
        [
            ServiceCatalogItem(
                itemName: "Exterior Window Cleaning",
                itemDescription: "Professional exterior glass cleaning",
                defaultQuantity: 12,
                defaultPrice: 8,
                itemType: .service,
                taxTreatment: .nonTaxable
            ),
            ServiceCatalogItem(
                itemName: "Replacement Window Screen",
                itemDescription: "Standard replacement screen",
                defaultQuantity: 2,
                defaultPrice: 45,
                itemType: .material,
                taxTreatment: .taxable
            ),
            ServiceCatalogItem(
                itemName: "Service Call Fee",
                itemDescription: "Standard service call",
                defaultQuantity: 1,
                defaultPrice: 25,
                itemType: .fee,
                taxTreatment: .nonTaxable
            )
        ]
    }

    static func sampleInvoice(
        catalogItems: [ServiceCatalogItem]
    ) -> InvoiceRecord {
        let lineItems = [
            ServiceLineItem(
                catalogItemID: catalogItems[0].id,
                serviceType: .windowCleaning,
                otherService: "",
                description: "Exterior glass and frames",
                quantity: 12,
                unitPrice: 8,
                lineTotal: 96
            ),
            ServiceLineItem(
                catalogItemID: catalogItems[1].id,
                serviceType: .other,
                otherService: "",
                description: "Two standard replacement screens",
                quantity: 2,
                unitPrice: 45,
                lineTotal: 90
            ),
            ServiceLineItem(
                catalogItemID: catalogItems[2].id,
                serviceType: .other,
                otherService: "",
                description: "",
                quantity: 1,
                unitPrice: 25,
                lineTotal: 25
            )
        ]

        let subtotal = 211.0
        let discount = 10.0
        let total = 201.0

        return InvoiceRecord(
            invoiceNumber: "INV-DEMO-00001",
            customerNumber: "DEMO-000001",
            siteID: nil,
            jobNumber: "JOB-DEMO-00001",
            lineItems: lineItems,
            subtotal: subtotal,
            discount: discount,
            total: total,
            amountPaid: 50,
            balanceDue: 151,
            status: .partiallyPaid,
            issueDate: Date(),
            dueDate: Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: Date()
            ) ?? Date(),
            paidDate: nil,
            notes: "Thank you for the opportunity to serve you."
        )
    }
}
