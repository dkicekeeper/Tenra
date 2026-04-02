//
//  SegmentedPickerView.swift
//  AIFinanceManager
//
//  Reusable segmented picker component
//

import SwiftUI

struct SegmentedPickerView<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(label: String, value: T)]
    
    init(
        title: String,
        selection: Binding<T>,
        options: [(label: String, value: T)]
    ) {
        self.title = title
        self._selection = selection
        self.options = options
    }
    
    var body: some View {
        Group {
            if #available(iOS 26, *) {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .glassEffect(.regular.interactive())
            } else {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .background(.ultraThinMaterial)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedType: TransactionType = .expense
    
    return SegmentedPickerView(
        title: "Type",
        selection: $selectedType,
        options: [
            (label: "Expense", value: TransactionType.expense),
            (label: "Income", value: TransactionType.income)
        ]
    )
    .padding()
}
