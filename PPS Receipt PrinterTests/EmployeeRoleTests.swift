//
//  EmployeeRoleTests.swift
//  PPS Receipt PrinterTests
//

import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class EmployeeRoleTests: XCTestCase {
    func testEmployeeMayHoldMultipleOperationalRoles() {
        let employee = EmployeeRecord(
            firstName: "Owner",
            lastName: "Technician",
            role: .owner,
            roles: [.owner, .salesperson, .technician]
        )

        XCTAssertTrue(employee.hasRole(.owner))
        XCTAssertTrue(employee.hasRole(.salesperson))
        XCTAssertTrue(employee.hasRole(.technician))
        XCTAssertFalse(employee.hasRole(.office))
        XCTAssertEqual(employee.roleDisplayText, "Owner, Sales, Technician")
    }

    func testLegacySingleRoleEmployeeDecodesIntoRoleSet() throws {
        let data = Data(
            """
            {
              "firstName": "Legacy",
              "lastName": "Technician",
              "role": "Technician"
            }
            """.utf8
        )

        let employee = try JSONDecoder().decode(EmployeeRecord.self, from: data)

        XCTAssertEqual(employee.roles, [.technician])
        XCTAssertTrue(employee.hasRole(.technician))
        XCTAssertEqual(employee.baseAddress, "")
    }

    func testEmployeeBaseAddressSurvivesPersistenceRoundTrip() throws {
        let employee = EmployeeRecord(
            firstName: "Field",
            lastName: "Technician",
            baseAddress: "123 Main Street, Edmond, OK 73034"
        )

        let data = try JSONEncoder().encode(employee)
        let decoded = try JSONDecoder().decode(EmployeeRecord.self, from: data)

        XCTAssertEqual(decoded.baseAddress, employee.baseAddress)
        XCTAssertEqual(decoded.normalizedBaseAddress, employee.baseAddress)
    }

    func testMultipleRolesSurvivePersistenceRoundTrip() throws {
        let employee = EmployeeRecord(
            firstName: "Small",
            lastName: "Business Owner",
            role: .owner,
            roles: [.owner, .manager, .technician]
        )

        let data = try JSONEncoder().encode(employee)
        let decoded = try JSONDecoder().decode(EmployeeRecord.self, from: data)

        XCTAssertEqual(decoded.roles, employee.roles)
        XCTAssertTrue(decoded.canOverrideScheduling)
        XCTAssertTrue(decoded.hasRole(.technician))
    }

    func testDispatchActorCarriesEveryEmployeeRole() {
        let employee = EmployeeRecord(
            firstName: "Field",
            lastName: "Owner",
            role: .owner,
            roles: [.owner, .technician]
        )

        let actor = DispatchActor.employee(employee)

        XCTAssertEqual(actor.roles, [.owner, .technician])
    }
}
