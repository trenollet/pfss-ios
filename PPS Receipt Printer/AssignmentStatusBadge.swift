//
//  AssignmentStatusBadge.swift
//  PPS Receipt Printer
//

import SwiftUI

struct AssignmentStatusBadge: View {
    let status: AssignmentStatus

    var body: some View {
        Label(status.rawValue, systemImage: statusSymbol)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Assignment status: \(status.rawValue)")
    }

    private var statusColor: Color {
        switch status {
        case .scheduled: return .blue
        case .dispatched: return .indigo
        case .enRoute: return .orange
        case .onSite: return .purple
        case .workComplete: return .teal
        case .invoiceReady: return .mint
        case .closed: return .green
        case .cancelled: return .red
        }
    }

    private var statusSymbol: String {
        switch status {
        case .scheduled: return "calendar"
        case .dispatched: return "paperplane.fill"
        case .enRoute: return "car.fill"
        case .onSite: return "location.fill"
        case .workComplete: return "checkmark.circle.fill"
        case .invoiceReady: return "doc.text.fill"
        case .closed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}
