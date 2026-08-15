//
//  PFSSJobDeclineReviewCenter.swift
//  PPS Receipt Printer
//
//  Phase 19 Step 3 – Durable technician decline and shared review inbox.
//

import Combine
import Foundation

@MainActor
final class PFSSJobDeclineReviewCenter: ObservableObject {
    static let shared = PFSSJobDeclineReviewCenter()

    struct QueuedSubmission: Codable, Identifiable, Hashable {
        var id: UUID
        var assignmentID: UUID
        var jobID: UUID
        var reason: String
        var createdAt: Date
    }

    @Published private(set) var pendingReviews: [PFSSJobDeclineReview] = []
    @Published private(set) var queuedSubmissions: [QueuedSubmission] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private let cloud = PFSSCloudflareBetaManager()
    private let defaults = UserDefaults.standard
    private let queueKey = "PFSSJobDeclineReviewCenter.queue.v1"
    private var pollingTask: Task<Void, Never>?

    private init() {
        if let data = defaults.data(forKey: queueKey),
           let decoded = try? JSONDecoder().decode(
            [QueuedSubmission].self,
            from: data
           ) {
            queuedSubmissions = decoded
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await retryQueuedSubmissions()
        do {
            pendingReviews = try await cloud.jobDeclineReviews()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func submit(
        assignmentID: UUID,
        jobID: UUID,
        reason: String
    ) async throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            throw PFSSCloudflareBetaError.server(
                "Enter a reason for declining this job."
            )
        }
        let submission = QueuedSubmission(
            id: UUID(),
            assignmentID: assignmentID,
            jobID: jobID,
            reason: trimmed,
            createdAt: Date()
        )
        queuedSubmissions.append(submission)
        saveQueue()
        do {
            let review = try await send(submission)
            queuedSubmissions.removeAll { $0.id == submission.id }
            if !pendingReviews.contains(where: { $0.id == review.id }) {
                pendingReviews.append(review)
            }
            saveQueue()
            lastError = nil
        } catch {
            // The durable request remains queued and retries automatically.
            lastError = error.localizedDescription
            throw error
        }
    }

    func resolve(
        _ review: PFSSJobDeclineReview,
        action: PFSSJobDeclineResolutionAction,
        note: String
    ) async throws {
        _ = try await cloud.resolveJobDecline(
            reviewID: review.id,
            action: action,
            note: note
        )
        pendingReviews.removeAll { $0.id == review.id }
        await refresh()
    }

    func hasPendingReview(assignmentID: UUID) -> Bool {
        let id = assignmentID.uuidString.lowercased()
        return pendingReviews.contains { $0.assignmentID == id } ||
            queuedSubmissions.contains { $0.assignmentID == assignmentID }
    }

    private func retryQueuedSubmissions() async {
        for submission in queuedSubmissions {
            do {
                let review = try await send(submission)
                queuedSubmissions.removeAll { $0.id == submission.id }
                if !pendingReviews.contains(where: { $0.id == review.id }) {
                    pendingReviews.append(review)
                }
                saveQueue()
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
    }

    private func send(
        _ submission: QueuedSubmission
    ) async throws -> PFSSJobDeclineReview {
        try await cloud.submitJobDecline(
            assignmentID: submission.assignmentID,
            jobID: submission.jobID,
            reason: submission.reason,
            idempotencyKey: submission.id
        )
    }

    private func saveQueue() {
        if queuedSubmissions.isEmpty {
            defaults.removeObject(forKey: queueKey)
        } else if let data = try? JSONEncoder().encode(queuedSubmissions) {
            defaults.set(data, forKey: queueKey)
        }
    }
}
