//
//  Components:ActionTile.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/16/26.
//

import SwiftUI

struct ActionTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let isInteractive: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        tint: Color = .blue,
        isEnabled: Bool = true,
        isInteractive: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
        self.isInteractive = isInteractive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(
                isEnabled
                    ? tint
                    : Color.secondary
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 64
            )
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(
                    cornerRadius: 12
                )
                .fill(
                    isEnabled
                        ? tint.opacity(0.10)
                        : Color.secondary.opacity(0.08)
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 12
                )
                .stroke(
                    isEnabled
                        ? tint.opacity(0.35)
                        : Color.secondary.opacity(0.20),
                    lineWidth: 1
                )
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 12
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || !isInteractive)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isInteractive ? [] : .isStaticText)
    }
}
