//
//  DepositRateChangeView.swift
//  AIFinanceManager
//
//  Reusable deposit rate change component
//

import SwiftUI

struct DepositRateChangeView: View {
    let account: Account
    let onRateChanged: (String, Decimal, String?) -> Void // (effectiveFrom, annualRate, note)

    @Environment(\.dismiss) private var dismiss

    @State private var rateText: String = ""
    @State private var effectiveFromDate: Date = Date()
    @State private var noteText: String = ""
    @FocusState private var isRateFocused: Bool

    var body: some View {
        EditSheetContainer(
            title: String(localized: "deposit.changeRateTitle"),
            isSaveDisabled: rateText.isEmpty,
            onSave: { saveRateChange() },
            onCancel: { dismiss() }
        ) {
            Section(header: Text(String(localized: "deposit.newRate"))) {
                HStack {
                    TextField("0.0", text: $rateText)
                        .keyboardType(.decimalPad)
                        .focused($isRateFocused)
                    Text(String(localized: "deposit.rateAnnual"))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Section(header: Text(String(localized: "deposit.effectiveDate"))) {
                DatePicker(String(localized: "deposit.date"), selection: $effectiveFromDate, displayedComponents: .date)
            }

            Section(header: Text(String(localized: "deposit.note"))) {
                TextField(String(localized: "deposit.note"), text: $noteText, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .onAppear {
            if let depositInfo = account.depositInfo {
                rateText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.interestRateAnnual).doubleValue)
            }
        }
        .task {
            await Task.yield()
            isRateFocused = true
        }
    }

    private func saveRateChange() {
        guard let rate = AmountFormatter.parse(rateText) else { return }

        let dateString = DateFormatters.dateFormatter.string(from: effectiveFromDate)
        let note = noteText.isEmpty ? nil : noteText

        onRateChanged(dateString, rate, note)
        HapticManager.success()
        dismiss()
    }
}

#Preview("Deposit Rate Change") {
    let sampleAccount = Account(
        id: "test",
        name: "Test Deposit",
        currency: "KZT",
        iconSource: .brandService("halykbank.kz"),
        depositInfo: DepositInfo(
            bankName: "Halyk Bank",
            principalBalance: Decimal(1000000),
            capitalizationEnabled: true,
            interestRateAnnual: Decimal(12.5),
            interestPostingDay: 15
        ),
        initialBalance: 1000000
    )

    DepositRateChangeView(
        account: sampleAccount,
        onRateChanged: { _, _, _ in }
    )
}
