//
//  InvoicePDFRenderer.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import Foundation
import UIKit

enum InvoicePDFRendererError: LocalizedError {
    case unableToCreateLogo
    case unableToWritePDF

    var errorDescription: String? {
        switch self {
        case .unableToCreateLogo:
            return "The saved business logo could not be processed."

        case .unableToWritePDF:
            return "The invoice PDF could not be created."
        }
    }
}

struct InvoicePDFRenderer {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792

    private static let pageMargin: CGFloat = 42
    private static let contentWidth: CGFloat =
        pageWidth - (pageMargin * 2)

    private static let footerHeight: CGFloat = 32

    static func createPDF(
        invoice: InvoiceRecord,
        businessProfile: BusinessProfile,
        customer: Customer?,
        site: CustomerSite?,
        catalogItems: [ServiceCatalogItem]
    ) throws -> URL {
        let pageBounds = CGRect(
            x: 0,
            y: 0,
            width: pageWidth,
            height: pageHeight
        )

        let format = UIGraphicsPDFRendererFormat()

        format.documentInfo = [
            kCGPDFContextTitle as String:
                "Invoice \(invoice.invoiceNumber)",

            kCGPDFContextCreator as String:
                businessProfile.businessName.isEmpty
                    ? "PFSS"
                    : businessProfile.businessName
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: pageBounds,
            format: format
        )

        let fileName = sanitizedFileName(
            "Invoice-\(invoice.invoiceNumber).pdf"
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        do {
            try renderer.writePDF(to: outputURL) { context in
                var pageNumber = 0
                var currentY: CGFloat = pageMargin

                func beginPage(
                    showColumnHeadings: Bool
                ) {
                    context.beginPage()
                    pageNumber += 1
                    currentY = pageMargin

                    currentY = drawPageHeader(
                        businessProfile: businessProfile,
                        invoice: invoice,
                        at: currentY
                    )

                    if showColumnHeadings {
                        currentY += 12

                        drawLineItemColumnHeadings(
                            at: currentY
                        )

                        currentY += 26
                    }
                }

                func finishPage() {
                    drawFooter(
                        businessProfile: businessProfile,
                        pageNumber: pageNumber
                    )
                }

                beginPage(showColumnHeadings: false)

                currentY = drawInvoiceInformation(
                    invoice: invoice,
                    customer: customer,
                    site: site,
                    startingAt: currentY
                )

                if !businessProfile.invoiceHeaderText
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {

                    currentY += 12

                    currentY = drawText(
                        businessProfile.invoiceHeaderText,
                        in: CGRect(
                            x: pageMargin,
                            y: currentY,
                            width: contentWidth,
                            height: 80
                        ),
                        font: .systemFont(ofSize: 10),
                        color: .darkGray
                    )
                }

                currentY += 18

                drawLineItemColumnHeadings(
                    at: currentY
                )

                currentY += 26

                for item in invoice.lineItems {
                    let itemHeight = lineItemHeight(
                        for: item
                    )

                    let maximumY =
                        pageHeight -
                        pageMargin -
                        footerHeight

                    if currentY + itemHeight > maximumY {
                        finishPage()
                        beginPage(showColumnHeadings: true)
                    }

                    drawLineItem(
                        item,
                        catalogItems: catalogItems,
                        at: currentY,
                        height: itemHeight
                    )

                    currentY += itemHeight
                }

                let summaryHeight: CGFloat = 150
                let maximumSummaryY =
                    pageHeight -
                    pageMargin -
                    footerHeight

                if currentY + summaryHeight > maximumSummaryY {
                    finishPage()
                    beginPage(showColumnHeadings: false)
                }

                currentY += 18

                currentY = drawFinancialSummary(
                    invoice: invoice,
                    startingAt: currentY
                )

                if !invoice.notes
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {

                    currentY += 18

                    currentY = drawNotes(
                        invoice.notes,
                        startingAt: currentY
                    )
                }

                if !businessProfile.invoiceFooterText
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {

                    currentY += 16

                    _ = drawText(
                        businessProfile.invoiceFooterText,
                        in: CGRect(
                            x: pageMargin,
                            y: currentY,
                            width: contentWidth,
                            height: 80
                        ),
                        font: .italicSystemFont(
                            ofSize: 9
                        ),
                        color: .darkGray
                    )
                }

                finishPage()
            }

            return outputURL
        } catch {
            throw InvoicePDFRendererError.unableToWritePDF
        }
    }

    // MARK: - Page Header

    private static func drawPageHeader(
        businessProfile: BusinessProfile,
        invoice: InvoiceRecord,
        at startingY: CGFloat
    ) -> CGFloat {
        var currentY = startingY

        let logoWidth: CGFloat = 155
        let logoHeight: CGFloat = 78

        if let logoData = businessProfile.logoData,
           let logo = UIImage(data: logoData) {

            let logoRect = aspectFitRect(
                imageSize: logo.size,
                inside: CGRect(
                    x: pageMargin,
                    y: currentY,
                    width: logoWidth,
                    height: logoHeight
                )
            )

            logo.draw(in: logoRect)
        } else {
            let businessName =
                businessProfile.businessName.isEmpty
                ? "Business Name"
                : businessProfile.businessName

            drawText(
                businessName,
                in: CGRect(
                    x: pageMargin,
                    y: currentY,
                    width: 270,
                    height: 36
                ),
                font: .boldSystemFont(ofSize: 20),
                color: .black
            )
        }

        drawText(
            "INVOICE",
            in: CGRect(
                x: pageWidth - pageMargin - 190,
                y: currentY,
                width: 190,
                height: 32
            ),
            font: .boldSystemFont(ofSize: 25),
            color: .black,
            alignment: .right
        )

        drawText(
            invoice.invoiceNumber,
            in: CGRect(
                x: pageWidth - pageMargin - 190,
                y: currentY + 34,
                width: 190,
                height: 22
            ),
            font: .systemFont(ofSize: 12),
            color: .darkGray,
            alignment: .right
        )

        currentY += 86

        let businessAddress = formattedBusinessAddress(
            businessProfile
        )

        var contactLines: [String] = []

        if !businessProfile.businessName.isEmpty {
            contactLines.append(
                businessProfile.businessName
            )
        }

        if !businessAddress.isEmpty {
            contactLines.append(businessAddress)
        }

        if !businessProfile.phone.isEmpty {
            contactLines.append(
                formattedPhoneNumber(businessProfile.phone)
            )
        }

        if !businessProfile.email.isEmpty {
            contactLines.append(
                businessProfile.email
            )
        }

        if !businessProfile.website.isEmpty {
            contactLines.append(
                businessProfile.website
            )
        }

        currentY = drawText(
            contactLines.joined(separator: "\n"),
            in: CGRect(
                x: pageMargin,
                y: currentY,
                width: contentWidth,
                height: 90
            ),
            font: .systemFont(ofSize: 9),
            color: .darkGray
        )

        currentY += 8

        drawHorizontalRule(at: currentY)

        return currentY + 14
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

    // MARK: - Invoice Information

    private static func drawInvoiceInformation(
        invoice: InvoiceRecord,
        customer: Customer?,
        site: CustomerSite?,
        startingAt: CGFloat
    ) -> CGFloat {
        var currentY = startingAt

        drawText(
            "BILL TO",
            in: CGRect(
                x: pageMargin,
                y: currentY,
                width: 250,
                height: 22
            ),
            font: .boldSystemFont(ofSize: 10),
            color: .darkGray
        )

        drawText(
            "INVOICE DETAILS",
            in: CGRect(
                x: pageWidth - pageMargin - 220,
                y: currentY,
                width: 220,
                height: 22
            ),
            font: .boldSystemFont(ofSize: 10),
            color: .darkGray,
            alignment: .right
        )

        currentY += 24

        let customerName = customerDisplayName(
            customer: customer,
            fallbackNumber: invoice.customerNumber
        )

        var customerLines = [customerName]

        if let site,
           !site.serviceAddress.isEmpty {
            customerLines.append(site.serviceAddress)
        }

        if let customer {
            if !customer.phone.isEmpty {
                customerLines.append(customer.phone)
            }

            if !customer.email.isEmpty {
                customerLines.append(customer.email)
            }
        }

        drawText(
            customerLines.joined(separator: "\n"),
            in: CGRect(
                x: pageMargin,
                y: currentY,
                width: 270,
                height: 100
            ),
            font: .systemFont(ofSize: 10),
            color: .black
        )

        let detailsText = """
        Issue Date: \(formattedDate(invoice.issueDate))
        Due Date: \(formattedDate(invoice.dueDate))
        Status: \(invoice.status.rawValue)
        Job: \(invoice.jobNumber)
        """

        drawText(
            detailsText,
            in: CGRect(
                x: pageWidth - pageMargin - 235,
                y: currentY,
                width: 235,
                height: 100
            ),
            font: .systemFont(ofSize: 10),
            color: .black,
            alignment: .right
        )

        return currentY + 92
    }

    // MARK: - Line Items

    private static func drawLineItemColumnHeadings(
        at y: CGFloat
    ) {
        let headerRect = CGRect(
            x: pageMargin,
            y: y,
            width: contentWidth,
            height: 24
        )

        UIColor(white: 0.16, alpha: 1).setFill()
        UIBezierPath(
            roundedRect: headerRect,
            cornerRadius: 4
        ).fill()

        drawText(
            "DESCRIPTION",
            in: CGRect(
                x: pageMargin + 8,
                y: y + 5,
                width: 270,
                height: 16
            ),
            font: .boldSystemFont(ofSize: 9),
            color: .white
        )

        drawText(
            "QTY",
            in: CGRect(
                x: 335,
                y: y + 5,
                width: 55,
                height: 16
            ),
            font: .boldSystemFont(ofSize: 9),
            color: .white,
            alignment: .right
        )

        drawText(
            "PRICE",
            in: CGRect(
                x: 397,
                y: y + 5,
                width: 72,
                height: 16
            ),
            font: .boldSystemFont(ofSize: 9),
            color: .white,
            alignment: .right
        )

        drawText(
            "AMOUNT",
            in: CGRect(
                x: 474,
                y: y + 5,
                width: 88,
                height: 16
            ),
            font: .boldSystemFont(ofSize: 9),
            color: .white,
            alignment: .right
        )
    }

    private static func drawLineItem(
        _ item: ServiceLineItem,
        catalogItems: [ServiceCatalogItem],
        at y: CGFloat,
        height: CGFloat
    ) {
        let itemName = lineItemName(
            for: item,
            catalogItems: catalogItems
        )

        var descriptionText = itemName

        if !item.description.isEmpty {
            descriptionText += "\n\(item.description)"
        }

        drawText(
            descriptionText,
            in: CGRect(
                x: pageMargin + 8,
                y: y + 7,
                width: 270,
                height: height - 12
            ),
            font: .systemFont(ofSize: 9),
            color: .black
        )

        drawText(
            formattedQuantity(item.quantity),
            in: CGRect(
                x: 335,
                y: y + 7,
                width: 55,
                height: 20
            ),
            font: .systemFont(ofSize: 9),
            color: .black,
            alignment: .right
        )

        drawText(
            currency(item.unitPrice),
            in: CGRect(
                x: 397,
                y: y + 7,
                width: 72,
                height: 20
            ),
            font: .systemFont(ofSize: 9),
            color: .black,
            alignment: .right
        )

        drawText(
            currency(item.lineTotal),
            in: CGRect(
                x: 474,
                y: y + 7,
                width: 88,
                height: 20
            ),
            font: .boldSystemFont(ofSize: 9),
            color: .black,
            alignment: .right
        )

        UIColor.systemGray5.setStroke()

        let linePath = UIBezierPath()
        linePath.move(
            to: CGPoint(
                x: pageMargin,
                y: y + height - 2
            )
        )
        linePath.addLine(
            to: CGPoint(
                x: pageWidth - pageMargin,
                y: y + height - 2
            )
        )
        linePath.lineWidth = 0.5
        linePath.stroke()
    }

    private static func lineItemHeight(
        for item: ServiceLineItem
    ) -> CGFloat {
        item.description.isEmpty ? 34 : 50
    }

    // MARK: - Financial Summary

    private static func drawFinancialSummary(
        invoice: InvoiceRecord,
        startingAt: CGFloat
    ) -> CGFloat {
        let labelX: CGFloat = 350
        let valueX: CGFloat = 468
        let labelWidth: CGFloat = 110
        let valueWidth: CGFloat = 94

        var currentY = startingAt

        drawSummaryRow(
            label: "Subtotal",
            value: currency(invoice.subtotal),
            labelX: labelX,
            valueX: valueX,
            y: currentY,
            labelWidth: labelWidth,
            valueWidth: valueWidth
        )

        currentY += 23

        if let tax = invoice.taxSnapshot {
            drawSummaryRow(
                label: "Tax",
                value: currency(
                    NSDecimalNumber(decimal: tax.addedTax).doubleValue
                ),
                labelX: labelX,
                valueX: valueX,
                y: currentY,
                labelWidth: labelWidth,
                valueWidth: valueWidth
            )

            currentY += 23
        }

        drawSummaryRow(
            label: "Discount",
            value: currency(invoice.discount),
            labelX: labelX,
            valueX: valueX,
            y: currentY,
            labelWidth: labelWidth,
            valueWidth: valueWidth
        )

        currentY += 23

        drawSummaryRow(
            label: "Total",
            value: currency(invoice.total),
            labelX: labelX,
            valueX: valueX,
            y: currentY,
            labelWidth: labelWidth,
            valueWidth: valueWidth,
            bold: true
        )

        currentY += 23

        drawSummaryRow(
            label: "Amount Paid",
            value: currency(invoice.amountPaid),
            labelX: labelX,
            valueX: valueX,
            y: currentY,
            labelWidth: labelWidth,
            valueWidth: valueWidth
        )

        currentY += 25

        let balanceRect = CGRect(
            x: labelX - 8,
            y: currentY - 5,
            width: 222,
            height: 32
        )

        UIColor(white: 0.16, alpha: 1).setFill()

        UIBezierPath(
            roundedRect: balanceRect,
            cornerRadius: 5
        ).fill()

        drawSummaryRow(
            label: "Balance Due",
            value: currency(invoice.balanceDue),
            labelX: labelX,
            valueX: valueX,
            y: currentY,
            labelWidth: labelWidth,
            valueWidth: valueWidth,
            bold: true,
            color: .white
        )

        return currentY + 38
    }

    private static func drawSummaryRow(
        label: String,
        value: String,
        labelX: CGFloat,
        valueX: CGFloat,
        y: CGFloat,
        labelWidth: CGFloat,
        valueWidth: CGFloat,
        bold: Bool = false,
        color: UIColor = .black
    ) {
        let font: UIFont = bold
            ? .boldSystemFont(ofSize: 11)
            : .systemFont(ofSize: 10)

        drawText(
            label,
            in: CGRect(
                x: labelX,
                y: y,
                width: labelWidth,
                height: 20
            ),
            font: font,
            color: color,
            alignment: .right
        )

        drawText(
            value,
            in: CGRect(
                x: valueX,
                y: y,
                width: valueWidth,
                height: 20
            ),
            font: font,
            color: color,
            alignment: .right
        )
    }

    // MARK: - Notes and Footer

    private static func drawNotes(
        _ notes: String,
        startingAt: CGFloat
    ) -> CGFloat {
        var currentY = startingAt

        drawText(
            "NOTES",
            in: CGRect(
                x: pageMargin,
                y: currentY,
                width: contentWidth,
                height: 20
            ),
            font: .boldSystemFont(ofSize: 10),
            color: .darkGray
        )

        currentY += 20

        return drawText(
            notes,
            in: CGRect(
                x: pageMargin,
                y: currentY,
                width: contentWidth,
                height: 90
            ),
            font: .systemFont(ofSize: 9),
            color: .black
        )
    }

    private static func drawFooter(
        businessProfile: BusinessProfile,
        pageNumber: Int
    ) {
        let footerY = pageHeight - pageMargin

        drawHorizontalRule(at: footerY - 14)

        let businessName =
            businessProfile.businessName.isEmpty
            ? "PFSS"
            : businessProfile.businessName

        drawText(
            businessName,
            in: CGRect(
                x: pageMargin,
                y: footerY - 8,
                width: 250,
                height: 16
            ),
            font: .systemFont(ofSize: 8),
            color: .gray
        )

        drawText(
            "Page \(pageNumber)",
            in: CGRect(
                x: pageWidth - pageMargin - 100,
                y: footerY - 8,
                width: 100,
                height: 16
            ),
            font: .systemFont(ofSize: 8),
            color: .gray,
            alignment: .right
        )
    }

    // MARK: - Drawing Helpers

    @discardableResult
    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(
            string: text,
            attributes: attributes
        )

        let measuredRect = attributedText.boundingRect(
            with: CGSize(
                width: rect.width,
                height: rect.height
            ),
            options: [
                .usesLineFragmentOrigin,
                .usesFontLeading
            ],
            context: nil
        )

        attributedText.draw(
            in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: min(
                    rect.height,
                    ceil(measuredRect.height)
                )
            )
        )

        return rect.minY + ceil(measuredRect.height)
    }

    private static func drawHorizontalRule(
        at y: CGFloat
    ) {
        UIColor.systemGray4.setStroke()

        let path = UIBezierPath()
        path.move(
            to: CGPoint(
                x: pageMargin,
                y: y
            )
        )
        path.addLine(
            to: CGPoint(
                x: pageWidth - pageMargin,
                y: y
            )
        )
        path.lineWidth = 0.75
        path.stroke()
    }

    private static func aspectFitRect(
        imageSize: CGSize,
        inside boundingRect: CGRect
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0 else {
            return boundingRect
        }

        let widthRatio =
            boundingRect.width / imageSize.width

        let heightRatio =
            boundingRect.height / imageSize.height

        let scale = min(widthRatio, heightRatio)

        let scaledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: boundingRect.minX,
            y: boundingRect.minY +
                ((boundingRect.height - scaledSize.height) / 2),
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    // MARK: - Formatting Helpers

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

    private static func formattedBusinessAddress(
        _ profile: BusinessProfile
    ) -> String {
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

        return lines.joined(separator: "\n")
    }

    private static func formattedDate(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime
                .month()
                .day()
                .year()
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

    private static func sanitizedFileName(
        _ fileName: String
    ) -> String {
        let invalidCharacters =
            CharacterSet.alphanumerics
                .union(
                    CharacterSet(
                        charactersIn: "-_."
                    )
                )
                .inverted

        return fileName
            .components(
                separatedBy: invalidCharacters
            )
            .joined(separator: "-")
    }
}
