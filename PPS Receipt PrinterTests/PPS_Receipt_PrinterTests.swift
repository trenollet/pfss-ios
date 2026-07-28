//
//  PPS_Receipt_PrinterTests.swift
//  PPS Receipt PrinterTests
//
//  Created by Timothy Renollet on 6/23/26.
//

import Testing
import Foundation
@testable import PPS_Receipt_Printer

struct PPS_Receipt_PrinterTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func printerServiceIdentifiesUnnamedReceiptPrinter() {
        #expect(
            BluetoothPrinterDiscoveryClassifier.isLikelyPrinter(
                name: nil,
                advertisedServiceUUIDs: ["18F0"]
            )
        )
    }

    @Test func commonReceiptPrinterNamesAreRecognized() {
        #expect(
            BluetoothPrinterDiscoveryClassifier.isLikelyPrinter(
                name: "RPP02N",
                advertisedServiceUUIDs: []
            )
        )
        #expect(
            BluetoothPrinterDiscoveryClassifier.isLikelyPrinter(
                name: "80mm Thermal Printer",
                advertisedServiceUUIDs: []
            )
        )
    }

    @Test func unrelatedBluetoothDevicesStayInFallbackList() {
        #expect(
            !BluetoothPrinterDiscoveryClassifier.isLikelyPrinter(
                name: "Tim's AirPods",
                advertisedServiceUUIDs: ["FFF0"]
            )
        )
    }

    @Test func saturdayRecurrenceMovesToFriday() throws {
        let calendar = recurrenceTestCalendar
        let saturday = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 22,
                hour: 10,
                minute: 30
            ))
        )

        let adjusted = try #require(
            JobRecurrenceFrequency.weekly.occurrenceDate(
                from: saturday,
                occurrence: 1,
                calendar: calendar
            )
        )

        #expect(calendar.component(.weekday, from: adjusted) == 6)
        #expect(calendar.component(.hour, from: adjusted) == 10)
        #expect(calendar.component(.minute, from: adjusted) == 30)
    }

    @Test func sundayRecurrenceMovesToMonday() throws {
        let calendar = recurrenceTestCalendar
        let sunday = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 23,
                hour: 13,
                minute: 15
            ))
        )

        let adjusted = try #require(
            JobRecurrenceFrequency.weekly.occurrenceDate(
                from: sunday,
                occurrence: 1,
                calendar: calendar
            )
        )

        #expect(calendar.component(.weekday, from: adjusted) == 2)
        #expect(calendar.component(.hour, from: adjusted) == 13)
        #expect(calendar.component(.minute, from: adjusted) == 15)
    }

    @Test func monthlyRecurrenceKeepsOriginalAnchorAfterWeekendAdjustment() throws {
        let calendar = recurrenceTestCalendar
        let anchor = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 22,
                hour: 9
            ))
        )

        let first = try #require(
            JobRecurrenceFrequency.monthly.occurrenceDate(
                from: anchor,
                occurrence: 1,
                calendar: calendar
            )
        )
        let second = try #require(
            JobRecurrenceFrequency.monthly.occurrenceDate(
                from: anchor,
                occurrence: 2,
                calendar: calendar
            )
        )

        // August 22, 2026 is Saturday and moves to Friday, August 21.
        #expect(calendar.component(.day, from: first) == 21)
        // September remains anchored to the 22nd rather than drifting to 21st.
        #expect(calendar.component(.day, from: second) == 22)
    }

    private var recurrenceTestCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

}
