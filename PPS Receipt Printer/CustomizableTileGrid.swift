//
//  CustomizableTileGrid.swift
//  PPS Receipt Printer
//
//  Persistent, user-arrangeable tile grids used by PFSS navigation hubs.
//

import SwiftUI
import UniformTypeIdentifiers

private struct CustomizableTilePosition: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case tile
        case space
    }

    var id: String
    var kind: Kind

    static func tile(_ id: String) -> Self {
        Self(id: id, kind: .tile)
    }

    static func space() -> Self {
        Self(id: "space:\(UUID().uuidString)", kind: .space)
    }
}

struct CustomizableTileGrid<Tile: View>: View {
    let storageKey: String
    let defaultTileIDs: [String]
    let tile: (String) -> Tile

    @State private var positions: [CustomizableTilePosition]
    @State private var isArranging = false
    @State private var draggedID: String?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    init(
        storageKey: String,
        defaultTileIDs: [String],
        @ViewBuilder tile: @escaping (String) -> Tile
    ) {
        self.storageKey = storageKey
        self.defaultTileIDs = defaultTileIDs
        self.tile = tile
        _positions = State(
            initialValue: Self.load(
                storageKey: storageKey,
                defaultTileIDs: defaultTileIDs
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            arrangementControls

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(positions) { position in
                    positionView(position)
                        .onDrag {
                            draggedID = position.id
                            return NSItemProvider(object: position.id as NSString)
                        } preview: {
                            dragPreview(position)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TilePositionDropDelegate(
                                targetID: position.id,
                                positions: $positions,
                                draggedID: $draggedID,
                                didReorder: persist
                            )
                        )
                }
            }
            .animation(.snappy, value: positions)
        }
        .onAppear(perform: reconcileLayout)
    }

    @ViewBuilder
    private var arrangementControls: some View {
        if isArranging {
            HStack(spacing: 12) {
                Label("Arrange Tiles", systemImage: "hand.draw.fill")
                    .font(.headline)

                Spacer()

                Button {
                    addSpace()
                } label: {
                    Label("Add Space", systemImage: "square.dashed")
                }

                Menu {
                    Button("Reset to Default", role: .destructive) {
                        resetToDefault()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }

                Button("Done") {
                    isArranging = false
                    draggedID = nil
                }
                .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)

            Text("Drag tiles or blank spaces into any position.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Spacer()
                Button {
                    isArranging = true
                } label: {
                    Label("Arrange", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Reorder tiles or add blank spaces")
            }
        }
    }

    @ViewBuilder
    private func positionView(_ position: CustomizableTilePosition) -> some View {
        if position.kind == .space {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isArranging ? Color.secondary.opacity(0.08) : .clear)
                    .overlay {
                        if isArranging {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    Color.secondary.opacity(0.45),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [7])
                                )
                        }
                    }

                if isArranging {
                    VStack(spacing: 8) {
                        Image(systemName: "square.dashed")
                            .font(.title2)
                        Text("Blank Space")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Button {
                        removeSpace(position.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("Remove blank space")
                }
            }
            .frame(minHeight: 135)
            .contentShape(Rectangle())
            .accessibilityHidden(!isArranging)
        } else {
            tile(position.id)
                .allowsHitTesting(!isArranging)
                .overlay(alignment: .topTrailing) {
                    if isArranging {
                        Image(systemName: "line.3.horizontal")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                            .accessibilityLabel("Drag to rearrange")
                    }
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.45) {
                    isArranging = true
                }
        }
    }

    @ViewBuilder
    private func dragPreview(_ position: CustomizableTilePosition) -> some View {
        if position.kind == .space {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 160, height: 135)
        } else {
            tile(position.id)
                .frame(width: 180)
                .allowsHitTesting(false)
        }
    }

    private func addSpace() {
        positions.append(.space())
        persist()
    }

    private func removeSpace(_ id: String) {
        positions.removeAll { $0.id == id && $0.kind == .space }
        persist()
    }

    private func resetToDefault() {
        positions = defaultTileIDs.map(CustomizableTilePosition.tile)
        persist()
    }

    private func reconcileLayout() {
        let validIDs = Set(defaultTileIDs)
        var seen = Set<String>()
        var reconciled = positions.filter { position in
            if position.kind == .space { return true }
            guard validIDs.contains(position.id), !seen.contains(position.id) else {
                return false
            }
            seen.insert(position.id)
            return true
        }

        for id in defaultTileIDs where !seen.contains(id) {
            reconciled.append(.tile(id))
        }

        if reconciled != positions {
            positions = reconciled
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func load(
        storageKey: String,
        defaultTileIDs: [String]
    ) -> [CustomizableTilePosition] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(
                [CustomizableTilePosition].self,
                from: data
              ) else {
            return defaultTileIDs.map(CustomizableTilePosition.tile)
        }
        return saved
    }
}

private struct TilePositionDropDelegate: DropDelegate {
    let targetID: String
    @Binding var positions: [CustomizableTilePosition]
    @Binding var draggedID: String?
    let didReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != targetID,
              let sourceIndex = positions.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = positions.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        withAnimation(.snappy) {
            positions.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
        didReorder()
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        didReorder()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
