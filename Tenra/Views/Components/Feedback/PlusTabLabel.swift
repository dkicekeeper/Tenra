//
//  PlusTabLabel.swift
//  AIFinanceManager
//
//  Custom label for the action tab (+/×).
//

import SwiftUI

struct PlusTabLabel: View {
    let isExpanded: Bool

    var body: some View {
        Label(
            isExpanded ? String(localized: "tab.close") : String(localized: "tab.add"),
            systemImage: isExpanded ? "xmark" : "plus"
        )
    }
}
