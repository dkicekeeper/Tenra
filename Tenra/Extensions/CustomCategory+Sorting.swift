//
//  CustomCategory+Sorting.swift
//  AIFinanceManager
//
//  Extension for sorting categories by custom order
//

import Foundation

extension Array where Element == CustomCategory {
    /// Sort categories by custom order if available, then by name
    func sortedByOrder() -> [CustomCategory] {
        return self.sorted { cat1, cat2 in
            // If both have order, sort by order
            if let order1 = cat1.order, let order2 = cat2.order {
                return order1 < order2
            }
            // If only one has order, it goes first
            if cat1.order != nil {
                return true
            }
            if cat2.order != nil {
                return false
            }
            // If neither has order, sort by name
            return cat1.name < cat2.name
        }
    }
}

extension Array where Element == String {
    /// Sort category names by custom order using the provided customCategories array
    func sortedByCustomOrder(customCategories: [CustomCategory], type: TransactionType) -> [String] {
        // Create a lookup for category order
        let orderLookup = Dictionary(uniqueKeysWithValues: customCategories.compactMap { category -> (String, Int)? in
            guard category.type == type, let order = category.order else { return nil }
            return (category.name, order)
        })

        return self.sorted { name1, name2 in
            let order1 = orderLookup[name1]
            let order2 = orderLookup[name2]

            // If both have custom order, sort by order
            if let o1 = order1, let o2 = order2 {
                return o1 < o2
            }
            // If only one has custom order, it goes first
            if order1 != nil {
                return true
            }
            if order2 != nil {
                return false
            }
            // If neither has custom order, sort by name
            return name1 < name2
        }
    }
}
