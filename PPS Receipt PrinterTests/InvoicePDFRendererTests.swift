import PDFKit
import XCTest
@testable import PPS_Receipt_Printer

final class InvoicePDFRendererTests: XCTestCase {
    func testInvoicePDFUsesReadableDarkBannerText() throws {
        var profile = BusinessProfile()
        profile.businessName = "PFSS Invoice QA"

        let customer = InvoicePreviewFactory.sampleCustomer()
        let site = InvoicePreviewFactory.sampleSite(
            customerNumber: customer.customerNumber
        )
        let catalogItems = InvoicePreviewFactory.sampleCatalogItems()
        let invoice = InvoicePreviewFactory.sampleInvoice(
            catalogItems: catalogItems
        )

        let url = try InvoicePDFRenderer.createPDF(
            invoice: invoice,
            businessProfile: profile,
            customer: customer,
            site: site,
            catalogItems: catalogItems
        )

        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(
            document.string?.contains("Balance Due") == true
        )

        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "PFSS Invoice Contrast QA"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
