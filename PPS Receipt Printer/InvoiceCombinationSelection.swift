import Foundation

struct InvoiceCombinationSelection {
    private(set) var isSelecting = false
    private(set) var selectedIDs = Set<UUID>()
    var canContinue: Bool { isSelecting && selectedIDs.count >= 2 }

    mutating func begin() { isSelecting = true; selectedIDs.removeAll() }
    mutating func cancel() { isSelecting = false; selectedIDs.removeAll() }
    mutating func toggle(_ id: UUID) {
        guard isSelecting else { return }
        if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
    }
    mutating func reconcile(eligibleIDs: Set<UUID>) {
        selectedIDs.formIntersection(eligibleIDs)
    }
}
