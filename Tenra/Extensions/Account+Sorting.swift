//
//  Account+Sorting.swift
//  AIFinanceManager
//
//  Extension for sorting accounts by custom order
//

import Foundation

extension Array where Element == Account {
    /// Sort accounts by custom order if available, then by name
    func sortedByOrder() -> [Account] {
        return self.sorted { acc1, acc2 in
            // If both have order, sort by order
            if let order1 = acc1.order, let order2 = acc2.order {
                return order1 < order2
            }
            // If only one has order, it goes first
            if acc1.order != nil {
                return true
            }
            if acc2.order != nil {
                return false
            }
            // If neither has order, sort by name
            return acc1.name < acc2.name
        }
    }
}
