//
//  DashboardCardStyle.swift
//  PFSS
//
//  Shared styling for all Operations Dashboard cards.
//

import SwiftUI

// MARK: - View Modifier

struct DashboardCardStyle: ViewModifier {

    var cornerRadius: CGFloat = 18
    var borderOpacity: Double = 0.15
    var padding: CGFloat = 16

    func body(content: Content) -> some View {

        content
            .padding(padding)
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    Color.gray.opacity(borderOpacity),
                    lineWidth: 1
                )
            )
            .shadow(
                color: .black.opacity(0.05),
                radius: 4,
                x: 0,
                y: 2
            )
    }
}

// MARK: - Convenience Extension

extension View {

    func dashboardCardStyle(
        cornerRadius: CGFloat = 18,
        borderOpacity: Double = 0.15,
        padding: CGFloat = 16
    ) -> some View {

        modifier(
            DashboardCardStyle(
                cornerRadius: cornerRadius,
                borderOpacity: borderOpacity,
                padding: padding
            )
        )
    }
}
