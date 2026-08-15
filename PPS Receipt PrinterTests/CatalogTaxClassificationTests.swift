import XCTest
@testable import PPS_Receipt_Printer

final class CatalogTaxClassificationTests: XCTestCase {
    func testLegacyLineItemDecodesWithoutInventingClassification() throws {
        let id = UUID()
        let json = """
        {
          "id":"\(id.uuidString)",
          "serviceType":"Other",
          "otherService":"Legacy Service",
          "description":"Existing transaction",
          "quantity":1,
          "unitPrice":100,
          "lineTotal":100,
          "estimatedMinutesPerUnit":30
        }
        """.data(using: .utf8)!

        let line = try JSONDecoder().decode(ServiceLineItem.self, from: json)

        XCTAssertNil(line.catalogItemNameSnapshot)
        XCTAssertNil(line.catalogItemTypeSnapshot)
        XCTAssertNil(line.taxTreatmentSnapshot)
        XCTAssertEqual(line.estimatedMinutesPerUnit, 30)
    }

    func testFractionalEstimatedMinutesSurviveCatalogAndLineRoundTrips() throws {
        let catalog = ServiceCatalogItem(
            itemName: "Detailed Pane",
            itemDescription: "Fractional labor unit",
            defaultQuantity: 1,
            defaultPrice: 5,
            estimatedMinutesPerUnit: 1.5
        )
        let catalogData = try JSONEncoder().encode(catalog)
        let decodedCatalog = try JSONDecoder().decode(
            ServiceCatalogItem.self,
            from: catalogData
        )
        XCTAssertEqual(decodedCatalog.estimatedMinutesPerUnit, 1.5)

        let line = ServiceLineItem(
            serviceType: .other,
            otherService: catalog.itemName,
            description: catalog.itemDescription,
            quantity: 4,
            unitPrice: catalog.defaultPrice,
            lineTotal: 20,
            estimatedMinutesPerUnit: catalog.estimatedMinutesPerUnit
        )
        let lineData = try JSONEncoder().encode(line)
        let decodedLine = try JSONDecoder().decode(ServiceLineItem.self, from: lineData)
        XCTAssertEqual(decodedLine.estimatedMinutesPerUnit, 1.5)
        XCTAssertEqual(SchedulingCalculator.estimatedMinutes(for: decodedLine), 6)
    }

    func testLineItemClassificationSurvivesRoundTrip() throws {
        let line = ServiceLineItem(
            catalogItemID: UUID(),
            catalogItemNameSnapshot: "Replacement Screen",
            catalogItemTypeSnapshot: .material,
            taxTreatmentSnapshot: .taxable,
            serviceType: .other,
            otherService: "Replacement Screen",
            description: "Screen material",
            quantity: 2,
            unitPrice: 25,
            lineTotal: 50
        )

        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(ServiceLineItem.self, from: data)

        XCTAssertEqual(decoded.catalogItemNameSnapshot, "Replacement Screen")
        XCTAssertEqual(decoded.catalogItemTypeSnapshot, .material)
        XCTAssertEqual(decoded.taxTreatmentSnapshot, .taxable)
    }

    func testTransactionSnapshotDoesNotChangeWhenCatalogChanges() {
        var catalog = ServiceCatalogItem(
            itemName: "Window Cleaning",
            itemDescription: "Exterior cleaning",
            defaultQuantity: 1,
            defaultPrice: 100,
            itemType: .service,
            taxTreatment: .nonTaxable
        )
        let line = ServiceLineItem(
            catalogItemID: catalog.id,
            catalogItemNameSnapshot: catalog.itemName,
            catalogItemTypeSnapshot: catalog.itemType,
            taxTreatmentSnapshot: catalog.taxTreatment,
            serviceType: .windowCleaning,
            otherService: "",
            description: catalog.itemDescription,
            quantity: 1,
            unitPrice: 100,
            lineTotal: 100
        )

        catalog.itemType = .material
        catalog.taxTreatment = .taxable

        XCTAssertEqual(line.catalogItemTypeSnapshot, .service)
        XCTAssertEqual(line.taxTreatmentSnapshot, .nonTaxable)
    }
}
