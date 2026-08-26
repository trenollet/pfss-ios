//
//  SynchronizationMutationEnvelopeTests.swift
//  PPS Receipt PrinterTests
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class SynchronizationMutationEnvelopeTests: XCTestCase {
    private struct PolicyContract: Decodable {
        var schemaVersion: Int
        var commandsByEntity: [String: [String: [String]]]
    }

    func testRecurringWorkClientSchemaMatchesSharedWorkerPolicyContract() throws {
        let contractURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "SynchronizationPolicyContract",
                withExtension: "json"
            )
        )
        let contract = try JSONDecoder().decode(
            PolicyContract.self,
            from: Data(contentsOf: contractURL)
        )
        XCTAssertEqual(contract.schemaVersion, 1)
        let serverFields = Set(try XCTUnwrap(
            contract.commandsByEntity["recurringWork"]?["recurringWork.update"]
        ))

        let prototypeJSON = Data(#"""
        {
          "jobNumber":"J-1",
          "customerNumber":"C-1",
          "serviceType":"Window Cleaning",
          "scheduledDate":"2026-08-22T12:00:00Z",
          "status":"Scheduled",
          "workNotes":"",
          "isRecurring":true,
          "createdDate":"2026-08-22T12:00:00Z"
        }
        """#.utf8)
        let prototype = try decoder.decode(JobRecord.self, from: prototypeJSON)
        let template = RecurringWorkTemplate(
            revision: 2,
            status: .held,
            rule: .weekly,
            endCondition: .endDate(Date(timeIntervalSince1970: 200_000)),
            anchorDate: Date(timeIntervalSince1970: 100_000),
            generationHorizonDays: 120,
            prototype: prototype,
            exceptions: [
                RecurringWorkOccurrenceException(
                    occurrenceIndex: 1,
                    kind: .skipped,
                    reason: "Contract field coverage"
                )
            ],
            scheduleStartIndex: 1,
            heldOccurrenceIndex: 2,
            heldScheduledDate: Date(timeIntervalSince1970: 150_000),
            holdStartedAt: Date(timeIntervalSince1970: 140_000),
            createdAt: Date(timeIntervalSince1970: 90_000),
            updatedAt: Date(timeIntervalSince1970: 160_000)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(template))
                as? [String: Any]
        )
        let clientMutableFields = Set(object.keys).subtracting(["id", "createdAt"])

        XCTAssertEqual(serverFields, clientMutableFields)
        XCTAssertTrue(serverFields.contains("heldScheduledDate"))
        for field in clientMutableFields {
            let classification = SynchronizationMutationClassifier.classify(
                entityType: .recurringWork,
                baseRecordData: jsonData([field: 1]),
                recordData: jsonData([field: 2])
            )
            XCTAssertEqual(classification.kind, .domainCommand, field)
            XCTAssertEqual(
                classification.commandName,
                "recurringWork.update",
                field
            )
        }
    }

    func testAssignmentRescheduleContractAllowsSystemMaintainedUpdateDate() throws {
        let contractURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "SynchronizationPolicyContract",
                withExtension: "json"
            )
        )
        let contract = try JSONDecoder().decode(
            PolicyContract.self,
            from: Data(contentsOf: contractURL)
        )
        let allowed = Set(try XCTUnwrap(
            contract.commandsByEntity["assignment"]?["assignment.reschedule"]
        ))
        XCTAssertTrue(
            Set(["scheduling", "history", "updatedDate"]).isSubset(of: allowed)
        )

        let classification = SynchronizationMutationClassifier.classify(
            entityType: .assignment,
            baseRecordData: jsonData([
                "scheduling": ["scheduledStart": "2026-08-24"],
                "history": ["events": []],
                "updatedDate": "2026-08-24T13:00:00Z",
            ]),
            recordData: jsonData([
                "scheduling": ["scheduledStart": "2026-08-25"],
                "history": ["events": [["type": "rescheduled"]]],
                "updatedDate": "2026-08-24T13:10:05Z",
            ])
        )
        XCTAssertEqual(classification.kind, .domainCommand)
        XCTAssertEqual(classification.commandName, "assignment.reschedule")
        XCTAssertEqual(
            Set(classification.changedFields),
            Set(["scheduling", "history", "updatedDate"])
        )
    }

    func testInvoiceEditContractCoversChargesAndDerivedPaymentState() throws {
        let contractURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "SynchronizationPolicyContract",
                withExtension: "json"
            )
        )
        let contract = try JSONDecoder().decode(
            PolicyContract.self,
            from: Data(contentsOf: contractURL)
        )
        let allowed = Set(try XCTUnwrap(
            contract.commandsByEntity["invoice"]?["invoice.edit"]
        ))
        let editedFields = Set([
            "lineItems", "subtotal", "total", "amountPaid", "balanceDue",
            "paidDate", "status",
        ])
        XCTAssertTrue(editedFields.isSubset(of: allowed))

        let classification = SynchronizationMutationClassifier.classify(
            entityType: .invoice,
            baseRecordData: jsonData([
                "lineItems": [["quantity": 1]],
                "subtotal": 100,
                "total": 100,
                "amountPaid": 100,
                "balanceDue": 0,
                "status": "Paid",
            ]),
            recordData: jsonData([
                "lineItems": [["quantity": 2]],
                "subtotal": 125,
                "total": 125,
                "amountPaid": 100,
                "balanceDue": 25,
                "status": "Partially Paid",
            ])
        )
        XCTAssertEqual(classification.kind, .domainCommand)
        XCTAssertEqual(classification.commandName, "invoice.edit")
        XCTAssertTrue(Set(classification.changedFields).isSubset(of: allowed))
    }

    func testVersionTwoEnvelopeDecodesAsCurrentWholeRecordMutation() throws {
        let operationID = UUID()
        let recordID = UUID()
        let timestamp = Date(timeIntervalSince1970: 50_000)
        let recordData = Data(#"{"name":"Field Customer"}"#.utf8)
        let payload = try OfflineRecordMutationCodec.envelopePayload(
            operationID: operationID,
            entityType: .customer,
            entityID: recordID,
            recordData: recordData,
            modifiedAt: timestamp,
            baseRevision: "revision-4",
            encoder: encoder
        )

        let mutation = try OfflineRecordMutationCodec.decode(
            payload,
            decoder: decoder
        )

        XCTAssertEqual(mutation.entityType, .customer)
        XCTAssertEqual(mutation.entityID, recordID)
        XCTAssertEqual(mutation.recordData, recordData)
        XCTAssertEqual(mutation.modifiedAt, timestamp)
    }

    func testLegacyWholeRecordMutationRemainsReadable() throws {
        let recordID = UUID()
        let legacy = OfflineRecordMutationPayload(
            entityType: .job,
            entityID: recordID,
            recordData: Data(#"{"status":"Assigned"}"#.utf8),
            modifiedAt: Date(timeIntervalSince1970: 40_000)
        )
        let payload = try OfflineOperationPayload(legacy, encoder: encoder)

        XCTAssertEqual(
            try OfflineRecordMutationCodec.decode(payload, decoder: decoder),
            legacy
        )
    }

    func testRebaseUpdatesEnvelopeRevisionWithoutChangingRecordData() throws {
        let operationID = UUID()
        let recordID = UUID()
        let recordData = Data(#"{"status":"In Progress"}"#.utf8)
        let original = try OfflineRecordMutationCodec.envelopePayload(
            operationID: operationID,
            entityType: .job,
            entityID: recordID,
            recordData: recordData,
            modifiedAt: Date(timeIntervalSince1970: 60_000),
            baseRevision: "revision-1",
            encoder: encoder
        )

        let rebased = try OfflineRecordMutationCodec.rebasingBaseRevision(
            original,
            to: "revision-2",
            decoder: decoder,
            encoder: encoder
        )
        let envelope = try rebased.decode(
            SynchronizationMutationEnvelope.self,
            decoder: decoder
        )

        XCTAssertEqual(envelope.baseRevision, "revision-2")
        XCTAssertEqual(envelope.operationID, operationID)
        XCTAssertEqual(envelope.recordID, recordID)
        XCTAssertEqual(envelope.recordData, recordData)
    }

    func testOperationRebaseKeepsOuterAndEmbeddedRevisionsTogether() throws {
        let operationID = UUID()
        let recordID = UUID()
        let recordData = Data(#"{"status":"Scheduled"}"#.utf8)
        let payload = try OfflineRecordMutationCodec.envelopePayload(
            operationID: operationID,
            entityType: .job,
            entityID: recordID,
            recordData: recordData,
            modifiedAt: Date(timeIntervalSince1970: 70_000),
            baseRevision: "revision-1",
            encoder: encoder
        )
        var operation = PendingOfflineOperation(
            id: operationID,
            type: .recordMutation,
            entityType: .job,
            entityID: recordID,
            actionName: "upsertRecord",
            payload: payload,
            baseRevision: "revision-1"
        )

        try OfflineRecordMutationCodec.rebase(
            &operation,
            to: "revision-2",
            decoder: decoder,
            encoder: encoder
        )

        let envelope = try operation.payload.decode(
            SynchronizationMutationEnvelope.self,
            decoder: decoder
        )
        XCTAssertEqual(operation.baseRevision, "revision-2")
        XCTAssertEqual(envelope.baseRevision, "revision-2")
        XCTAssertEqual(envelope.operationID, operationID)
        XCTAssertEqual(envelope.recordID, recordID)
        XCTAssertEqual(envelope.recordData, recordData)
    }

    func testUnknownEnvelopeFieldsSurviveDecodeAndReencode() throws {
        let operationID = UUID()
        let recordID = UUID()
        let json = """
        {
          "schemaVersion": 2,
          "operationID": "\(operationID.uuidString)",
          "entityType": "site",
          "recordID": "\(recordID.uuidString)",
          "mutationKind": "wholeRecord",
          "changedFields": [],
          "recordData": "e30=",
          "clientCreatedAt": "2026-08-15T10:00:00Z",
          "deviceModifiedAt": "2026-08-15T10:00:00Z",
          "futurePolicy": {"mode": "preserve", "priority": 7}
        }
        """
        let decoded = try decoder.decode(
            SynchronizationMutationEnvelope.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            decoded.unknownFields["futurePolicy"],
            .object([
                "mode": .string("preserve"),
                "priority": .number(7),
            ])
        )

        let reencoded = try encoder.encode(decoded)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        )
        let future = try XCTUnwrap(object["futurePolicy"] as? [String: Any])
        XCTAssertEqual(future["mode"] as? String, "preserve")
        XCTAssertEqual(future["priority"] as? Double, 7)
    }

    func testIndependentCustomerFieldEditUsesFieldPatch() throws {
        let classification = SynchronizationMutationClassifier.classify(
            entityType: .customer,
            baseRecordData: jsonData(["name": "Acme", "phone": "111"]),
            recordData: jsonData(["name": "Acme", "phone": "222"])
        )

        XCTAssertEqual(classification.kind, .fieldPatch)
        XCTAssertEqual(classification.changedFields, ["phone"])
        XCTAssertNil(classification.commandName)
    }

    func testJobTimelineOnlyChangeIsAppendOnlyFact() throws {
        let originalEvent = ["id": "event-1", "type": "travelStarted"]
        let addedEvent = ["id": "event-2", "type": "arrivedOnSite"]
        let classification = SynchronizationMutationClassifier.classify(
            entityType: .job,
            baseRecordData: jsonData(["timelineEvents": [originalEvent]]),
            recordData: jsonData(["timelineEvents": [originalEvent, addedEvent]])
        )

        XCTAssertEqual(classification.kind, .appendFact)
        XCTAssertEqual(classification.changedFields, ["timelineEvents"])
        XCTAssertNil(classification.commandName)
    }

    func testAssignmentNoteUsesSpecificServerCommand() throws {
        let classification = SynchronizationMutationClassifier.classify(
            entityType: .assignment,
            baseRecordData: jsonData([
                "dispatchNotes": "",
                "history": ["events": []],
            ]),
            recordData: jsonData([
                "dispatchNotes": "Gate code 1234",
                "history": ["events": [["id": "event-1", "type": "noteAdded"]]],
            ])
        )

        XCTAssertEqual(classification.kind, .domainCommand)
        XCTAssertEqual(classification.commandName, "assignment.updateNotes")
        XCTAssertEqual(classification.changedFields, ["dispatchNotes", "history"])
    }

    func testInvoicePaymentUsesSpecificServerCommand() throws {
        let classification = SynchronizationMutationClassifier.classify(
            entityType: .invoice,
            baseRecordData: jsonData([
                "amountPaid": 0,
                "balanceDue": 100,
                "receipts": [],
            ]),
            recordData: jsonData([
                "amountPaid": 100,
                "balanceDue": 0,
                "receipts": [["id": "receipt-1", "amount": 100]],
            ])
        )

        XCTAssertEqual(classification.kind, .domainCommand)
        XCTAssertEqual(classification.commandName, "invoice.recordPayment")
        XCTAssertEqual(
            classification.changedFields,
            ["amountPaid", "balanceDue", "receipts"]
        )
    }

    func testSensitiveJobChangesUseSpecificServerCommands() throws {
        let cases: [(String, Any, Any, String)] = [
            ("status", "Assigned", "In Progress", "job.transition"),
            ("scheduledDate", "2026-08-20", "2026-08-21", "job.reschedule"),
            ("primaryTechnicianID", "employee-1", "employee-2", "job.assign"),
            ("recurrenceFrequency", "weekly", "monthly", "recurringWork.update"),
            ("lifecycleStatus", "active", "archived", "record.lifecycle"),
        ]

        for (field, oldValue, newValue, expectedCommand) in cases {
            let classification = SynchronizationMutationClassifier.classify(
                entityType: .job,
                baseRecordData: jsonData([field: oldValue]),
                recordData: jsonData([field: newValue])
            )
            XCTAssertEqual(classification.kind, .domainCommand, field)
            XCTAssertEqual(classification.commandName, expectedCommand, field)
            XCTAssertEqual(classification.changedFields, [field], field)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
