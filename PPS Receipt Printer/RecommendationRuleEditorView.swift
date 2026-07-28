//
//  RecommendationRuleEditorView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/7/26.
//

import SwiftUI

struct RecommendationRuleEditorView: View {
    @EnvironmentObject var store: AppDataStore
    
    @State private var selectedTriggerID: UUID?
    @State private var selectedRecommendedIDs: Set<UUID> = []
    @State private var notes = ""
    
    private var catalogItems: [ServiceCatalogItem] {
        store.activeServiceCatalogItems
    }
    
    var body: some View {
        Form {
            Section("Trigger Service") {
                Picker("When this service is added", selection: $selectedTriggerID) {
                    Text("Select Service").tag(UUID?.none)
                    
                    ForEach(catalogItems) { item in
                        Text(item.itemName).tag(UUID?.some(item.id))
                    }
                }
            }
            
            Section("Recommend These Services") {
                ForEach(catalogItems) { item in
                    if item.id != selectedTriggerID {
                        Toggle(
                            item.itemName,
                            isOn: Binding(
                                get: {
                                    selectedRecommendedIDs.contains(item.id)
                                },
                                set: { isSelected in
                                    if isSelected {
                                        selectedRecommendedIDs.insert(item.id)
                                    } else {
                                        selectedRecommendedIDs.remove(item.id)
                                    }
                                }
                            )
                        )
                    }
                }
            }
            
            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            
            Section("Existing Rules") {
                ForEach(store.recommendationRules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ruleTitle(rule))
                            .font(.headline)
                        
                        Text(ruleSubtitle(rule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if !rule.notes.isEmpty {
                            Text(rule.notes)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteRules)
            }
        }
        .navigationTitle("Recommendation Rules")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRule()
                }
                .disabled(selectedTriggerID == nil || selectedRecommendedIDs.isEmpty)
            }
        }
    }
    
    private func saveRule() {
        guard let selectedTriggerID else { return }
        
        let rule = RecommendationRule(
            triggerCatalogItemID: selectedTriggerID,
            recommendedCatalogItemIDs: Array(selectedRecommendedIDs),
            notes: notes
        )
        
        store.addRecommendationRule(rule)
        
        self.selectedTriggerID = nil
        selectedRecommendedIDs = []
        notes = ""
    }
    
    private func deleteRules(at offsets: IndexSet) {
        let rules = store.recommendationRules
        
        for offset in offsets {
            store.deleteRecommendationRule(rules[offset])
        }
    }
    
    private func catalogName(for id: UUID) -> String {
        store.serviceCatalogItems.first(where: { $0.id == id })?.itemName ?? "Unknown Service"
    }
    
    private func ruleTitle(_ rule: RecommendationRule) -> String {
        catalogName(for: rule.triggerCatalogItemID)
    }
    
    private func ruleSubtitle(_ rule: RecommendationRule) -> String {
        rule.recommendedCatalogItemIDs
            .map { catalogName(for: $0) }
            .joined(separator: ", ")
    }
}
