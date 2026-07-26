//
//  Components:ActionTileRow.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/16/26.
//

import SwiftUI

struct ActionTileItem: Identifiable {
    let id = UUID()

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
}

struct ActionTileRow: View {
    let actions: [ActionTileItem]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(actions) { item in
                ActionTile(
                    title: item.title,
                    systemImage: item.systemImage,
                    tint: item.tint,
                    isEnabled: item.isEnabled,
                    isInteractive: item.isInteractive,
                    action: item.action
                )
            }
        }
    }
}
