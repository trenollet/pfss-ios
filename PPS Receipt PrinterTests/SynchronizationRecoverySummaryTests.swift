//
//  SynchronizationRecoverySummaryTests.swift
//  PPS Receipt PrinterTests
//

import XCTest
@testable import PPS_Receipt_Printer

final class SynchronizationRecoverySummaryTests: XCTestCase {
    func testSummaryExplainsRoutineRecoveryAsOneResult() {
        let summary = SynchronizationRecoverySummary(
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 105),
            startingCursor: 12,
            endingCursor: 19,
            pulledChanges: 7,
            alreadyReflected: 2,
            supersededDeviceChanges: 3,
            requiringReview: 1
        )

        XCTAssertEqual(summary.startingCursor, 12)
        XCTAssertEqual(summary.endingCursor, 19)
        XCTAssertTrue(summary.detail.contains("Downloaded 7 cloud changes"))
        XCTAssertTrue(summary.detail.contains("2 already reflected"))
        XCTAssertTrue(summary.detail.contains("3 older device changes safely superseded"))
        XCTAssertTrue(summary.detail.contains("1 need review"))
    }

    func testSummaryRoundTripsDurably() throws {
        let expected = SynchronizationRecoverySummary(
            startedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 210),
            startingCursor: 0,
            endingCursor: 4,
            pulledChanges: 4,
            alreadyReflected: 0,
            supersededDeviceChanges: 0,
            requiringReview: 0
        )

        let data = try JSONEncoder().encode(expected)
        XCTAssertEqual(
            try JSONDecoder().decode(
                SynchronizationRecoverySummary.self,
                from: data
            ),
            expected
        )
    }
}
