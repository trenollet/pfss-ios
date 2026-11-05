import PDFKit
import XCTest
@testable import PPS_Receipt_Printer

final class InvoicePDFRendererTests: XCTestCase {
    @MainActor
    func testCombinedPDFIncludesEveryJobAndPreservedTotal() throws {
        let catalog = InvoicePreviewFactory.sampleCatalogItems()
        var a = InvoicePreviewFactory.sampleInvoice(catalogItems: catalog)
        a.amountPaid = 0; a.balanceDue = a.total; a.status = .draft
        var b = a
        b.id = UUID(); b.invoiceNumber = "INV-SECOND"; b.jobNumber = "JOB-SECOND"
        let proposal = try InvoiceCombinationEngine.propose(invoiceNumber: "INV-COMBINED-QA-C",
            billingCustomerNumber: a.customerNumber, sources: [a, b], verifications: [], preparedBy: "Member")
        var bill = a
        bill.id = proposal.id; bill.invoiceNumber = proposal.invoiceNumber; bill.siteID = nil
        bill.lineItems = proposal.lines.map(\.item); bill.combination = proposal
        bill.associatedJobNumbers = proposal.jobNumbers
        bill.subtotal = 422; bill.discount = 20; bill.total = 402; bill.balanceDue = 402
        let url = try InvoicePDFRenderer.createPDF(invoice: bill, businessProfile: BusinessProfile(),
            customer: InvoicePreviewFactory.sampleCustomer(), site: nil, catalogItems: catalog)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(document.string?.contains("JOB-SECOND") == true)
        XCTAssertTrue(document.string?.contains("JOB-DEMO-00001") == true)
        XCTAssertTrue(document.string?.contains("402.00") == true)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "PFSS Combined Invoice QA"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
