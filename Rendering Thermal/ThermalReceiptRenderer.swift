//
//  ThermalReceiptRenderer.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import Foundation

struct ThermalReceiptRenderer {
    static let charactersPerLine = 48

    static func render(
        invoice: InvoiceRecord,
        businessProfile: BusinessProfile,
        customer: Customer?,
        site: CustomerSite?,
        catalogItems: [ServiceCatalogItem]
    ) -> String {
        var lines: [String] = [

            "",

            ""

        ]
        appendBusinessHeader(
            to: &lines,
            profile: businessProfile
        )

        lines.append(separatorLine())
        lines.append(centered("INVOICE"))
        lines.append(centered(invoice.invoiceNumber))
        lines.append("")

        appendInvoiceDetails(
            to: &lines,
            invoice: invoice,
            customer: customer,
            site: site
        )

        lines.append(separatorLine())

        appendLineItems(
            to: &lines,
            invoice: invoice,
            catalogItems: catalogItems
        )

        lines.append(separatorLine())

        appendTotals(
            to: &lines,
            invoice: invoice
        )

        if !invoice.notes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {

            lines.append(separatorLine())
            lines.append("NOTES")
            lines.append(contentsOf: wrappedLines(invoice.notes))
        }

        let footerText = businessProfile.invoiceFooterText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !footerText.isEmpty {
            lines.append(separatorLine())

            for line in wrappedLines(footerText) {
                lines.append(centered(line))
            }
        }

        lines.append("")
        lines.append("")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Business Header

    private static func appendBusinessHeader(
        to lines: inout [String],
        profile: BusinessProfile
    ) {
        let businessName = profile.businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !businessName.isEmpty {
            for line in wrappedLines(businessName.uppercased()) {
                lines.append(centered(line))
            }
        }

        let addressLines = businessAddressLines(profile)

        for addressLine in addressLines {
            for line in wrappedLines(addressLine) {
                lines.append(centered(line))
            }
        }

        if !profile.phone.isEmpty {
            lines.append(
                centered(
                    formattedPhoneNumber(profile.phone)
                )
            )
        }

        if !profile.email.isEmpty {
            for line in wrappedLines(profile.email) {
                lines.append(centered(line))
            }
        }

        if !profile.website.isEmpty {
            for line in wrappedLines(profile.website) {
                lines.append(centered(line))
            }
        }

        let headerText = profile.invoiceHeaderText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !headerText.isEmpty {
            lines.append("")

            for line in wrappedLines(headerText) {
                lines.append(centered(line))
            }
        }
    }

    // MARK: - Invoice Details

    private static func appendInvoiceDetails(
        to lines: inout [String],
        invoice: InvoiceRecord,
        customer: Customer?,
        site: CustomerSite?
    ) {
        lines.append(
            twoColumnLine(
                left: "Date:",
                right: formattedDate(invoice.issueDate)
            )
        )

        lines.append(
            twoColumnLine(
                left: "Due:",
                right: formattedDate(invoice.dueDate)
            )
        )

        lines.append(
            twoColumnLine(
                left: "Status:",
                right: invoice.status.rawValue
            )
        )

        if !invoice.jobNumber.isEmpty {
            lines.append(
                twoColumnLine(
                    left: "Job:",
                    right: invoice.jobNumber
                )
            )
        }

        lines.append("")
        lines.append("CUSTOMER")

        let customerName = customerDisplayName(
            customer: customer,
            fallbackNumber: invoice.customerNumber
        )

        lines.append(contentsOf: wrappedLines(customerName))

        if let site,
           !site.serviceAddress.isEmpty {
            lines.append(contentsOf: wrappedLines(site.serviceAddress))
        }

        if let customer {
            if !customer.phone.isEmpty {
                lines.append(
                    formattedPhoneNumber(customer.phone)
                )
            }

            if !customer.email.isEmpty {
                lines.append(contentsOf: wrappedLines(customer.email))
            }
        }
    }

    // MARK: - Line Items

    private static func appendLineItems(
        to lines: inout [String],
        invoice: InvoiceRecord,
        catalogItems: [ServiceCatalogItem]
    ) {
        if invoice.lineItems.isEmpty {
            lines.append(centered("NO LINE ITEMS"))
            return
        }

        for item in invoice.lineItems {
            let itemName = lineItemName(
                for: item,
                catalogItems: catalogItems
            )

            lines.append(contentsOf: wrappedLines(itemName))

            if !item.description.isEmpty {
                for line in wrappedLines(item.description) {
                    lines.append("  \(line)")
                }
            }

            let quantityText = formattedQuantity(item.quantity)
            let priceText = currency(item.unitPrice)
            let totalText = currency(item.lineTotal)

            lines.append(
                twoColumnLine(
                    left: "\(quantityText) x \(priceText)",
                    right: totalText
                )
            )

            lines.append("")
        }

        if lines.last == "" {
            lines.removeLast()
        }
    }

    // MARK: - Totals

    private static func appendTotals(
        to lines: inout [String],
        invoice: InvoiceRecord
    ) {
        lines.append(
            twoColumnLine(
                left: "Subtotal",
                right: currency(invoice.subtotal)
            )
        )

        if invoice.discount != 0 {
            lines.append(
                twoColumnLine(
                    left: "Discount",
                    right: "-\(currency(abs(invoice.discount)))"
                )
            )
        }

        lines.append(
            twoColumnLine(
                left: "TOTAL",
                right: currency(invoice.total)
            )
        )

        lines.append(
            twoColumnLine(
                left: "Paid",
                right: currency(invoice.amountPaid)
            )
        )

        lines.append(
            twoColumnLine(
                left: "BALANCE",
                right: currency(invoice.balanceDue)
            )
        )
    }

    // MARK: - Layout Helpers

    private static func separatorLine() -> String {
        String(
            repeating: "-",
            count: charactersPerLine
        )
    }

    private static func centered(
        _ text: String
    ) -> String {
        let trimmed = String(text.prefix(charactersPerLine))
        let remainingSpace = max(
            0,
            charactersPerLine - trimmed.count
        )

        let leftPadding = remainingSpace / 2

        return String(
            repeating: " ",
            count: leftPadding
        ) + trimmed
    }

    private static func twoColumnLine(
        left: String,
        right: String
    ) -> String {
        let safeRight = String(
            right.prefix(charactersPerLine)
        )

        let maximumLeftLength = max(
            0,
            charactersPerLine - safeRight.count - 1
        )

        let safeLeft = String(
            left.prefix(maximumLeftLength)
        )

        let spaces = max(
            1,
            charactersPerLine -
                safeLeft.count -
                safeRight.count
        )

        return safeLeft +
            String(repeating: " ", count: spaces) +
            safeRight
    }

    private static func wrappedLines(
        _ text: String
    ) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return []
        }

        var output: [String] = []

        for paragraph in normalized.components(separatedBy: "\n") {
            let words = paragraph.split(
                whereSeparator: \.isWhitespace
            )

            if words.isEmpty {
                output.append("")
                continue
            }

            var currentLine = ""

            for wordSubstring in words {
                let word = String(wordSubstring)

                if word.count > charactersPerLine {
                    if !currentLine.isEmpty {
                        output.append(currentLine)
                        currentLine = ""
                    }

                    var remainingWord = word

                    while remainingWord.count > charactersPerLine {
                        output.append(
                            String(
                                remainingWord.prefix(
                                    charactersPerLine
                                )
                            )
                        )

                        remainingWord = String(
                            remainingWord.dropFirst(
                                charactersPerLine
                            )
                        )
                    }

                    currentLine = remainingWord
                    continue
                }

                let candidate = currentLine.isEmpty
                    ? word
                    : "\(currentLine) \(word)"

                if candidate.count <= charactersPerLine {
                    currentLine = candidate
                } else {
                    output.append(currentLine)
                    currentLine = word
                }
            }

            if !currentLine.isEmpty {
                output.append(currentLine)
            }
        }

        return output
    }

    // MARK: - Data Helpers

    private static func lineItemName(
        for item: ServiceLineItem,
        catalogItems: [ServiceCatalogItem]
    ) -> String {
        if let catalogItemID = item.catalogItemID,
           let catalogItem = catalogItems.first(where: {
               $0.id == catalogItemID
           }) {
            return catalogItem.itemName
        }

        if !item.otherService.isEmpty {
            return item.otherService
        }

        return item.serviceType.rawValue
    }

    private static func customerDisplayName(
        customer: Customer?,
        fallbackNumber: String
    ) -> String {
        guard let customer else {
            return fallbackNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return fallbackNumber
    }

    private static func businessAddressLines(
        _ profile: BusinessProfile
    ) -> [String] {
        var lines: [String] = []

        if !profile.addressLine1.isEmpty {
            lines.append(profile.addressLine1)
        }

        if !profile.addressLine2.isEmpty {
            lines.append(profile.addressLine2)
        }

        let cityStateZIP = [
            profile.city,
            profile.state,
            profile.postalCode
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        if !cityStateZIP.isEmpty {
            lines.append(cityStateZIP)
        }

        return lines
    }

    // MARK: - Formatting Helpers

    private static func formattedDate(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime
                .month(.twoDigits)
                .day(.twoDigits)
                .year(.twoDigits)
        )
    }

    private static func currency(
        _ value: Double
    ) -> String {
        value.formatted(
            .currency(code: "USD")
        )
    }

    private static func formattedQuantity(
        _ quantity: Double
    ) -> String {
        if quantity.rounded() == quantity {
            return String(Int(quantity))
        }

        return quantity.formatted(
            .number.precision(
                .fractionLength(0...2)
            )
        )
    }

    private static func formattedPhoneNumber(
        _ value: String
    ) -> String {
        let digits = value.filter(\.isNumber)

        guard digits.count == 10 else {
            return value
        }

        let areaCode = digits.prefix(3)
        let prefix = digits.dropFirst(3).prefix(3)
        let lineNumber = digits.dropFirst(6)

        return "(\(areaCode)) \(prefix)-\(lineNumber)"
    }
}
