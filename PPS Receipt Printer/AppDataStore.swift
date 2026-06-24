//
//  AppDataStore.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation
import Combine

final class AppDataStore: ObservableObject {
    @Published var customers: [Customer] = []
    @Published var sites: [CustomerSite] = []

    private var nextCustomerNumber = 1

    func generateCustomerNumber() -> String {
        let number = String(format: "PPS-%06d", nextCustomerNumber)
        nextCustomerNumber += 1
        return number
    }

    func addCustomer(_ customer: Customer) {
        customers.append(customer)
    }

    func addSite(_ site: CustomerSite) {
        sites.append(site)
    }

    func sites(for customerNumber: String) -> [CustomerSite] {
        sites.filter { $0.customerNumber == customerNumber }
    }
}
