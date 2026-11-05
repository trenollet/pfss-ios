import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class InvoiceCombinationSelectionTests: XCTestCase {
    func testTwoSelectionsActivateContinueAndDeselectionDisablesIt() {
        var selection = InvoiceCombinationSelection()
        let a = UUID(), b = UUID(), c = UUID()
        selection.toggle(a)
        XCTAssertTrue(selection.selectedIDs.isEmpty)
        selection.begin()
        selection.toggle(a)
        XCTAssertFalse(selection.canContinue)
        selection.toggle(b)
        XCTAssertTrue(selection.canContinue)
        selection.toggle(c)
        XCTAssertTrue(selection.canContinue)
        selection.toggle(a)
        XCTAssertTrue(selection.canContinue)
        selection.toggle(b)
        XCTAssertFalse(selection.canContinue)
    }
    func testCancelClearsSelectionAndReentryStartsEmpty() {
        var selection = InvoiceCombinationSelection()
        selection.begin(); selection.toggle(UUID()); selection.cancel()
        XCTAssertFalse(selection.isSelecting)
        XCTAssertTrue(selection.selectedIDs.isEmpty)
        selection.begin()
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }
    func testRemovedOrUnavailableInvoicesAreDeselected() {
        var selection = InvoiceCombinationSelection()
        let a = UUID(), b = UUID(), c = UUID()
        selection.begin(); selection.toggle(a); selection.toggle(b); selection.toggle(c)
        selection.reconcile(eligibleIDs: [a, b])
        XCTAssertEqual(selection.selectedIDs, [a, b])
        XCTAssertTrue(selection.canContinue)
        selection.reconcile(eligibleIDs: [a])
        XCTAssertFalse(selection.canContinue)
    }
}
