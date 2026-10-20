//
//  DepositRateChangeView.swift
//  Tenra
//
//  Reusable deposit rate change component (matches LoanRateChangeView pattern).
//

import SwiftUI

struct DepositRateChangeView: View {
    let account: Account
    let onRateChanged: (String, Decimal, String?) -> Void // (effectiveFrom, annualRate, note)

    @Environment(\.dismiss) private var dismiss

    @State private var rateText: String = ""
    @State private var effectiveFromDate: Date = Date()
    @State private var noteText: String = ""

    var body: some View {
        EditSheetContainer(
            title: String(localized: "deposit.changeRateTitle"),
            isSaveDisabled: rateText.isEmpty,
            wrapInForm: false,
            onSave: { saveRateChange() },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection {
                        UniversalRow(
                            leadingIcon: .sfSymbol("percent", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "deposit.newRate")
                        ) {
                            FormTextField(
                                text: $rateText,
                                placeholder: "0.0",
                                style: .inline,
                                keyboardType: .decimalPad,
                                autofocus: true
                            )
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        UniversalRow(
                            String(localized: "deposit.effectiveDate"),
                            icon: "calendar",
                            accessory: .date($effectiveFromDate)
                        )

                        Divider().padding(.leading, AppSpacing.lg)

                        UniversalRow(
                            leadingIcon: .sfSymbol("note.text", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "deposit.note")
                        ) {
                            FormTextField(
                                text: $noteText,
                                placeholder: String(localized: "loan.notePlaceholder", defaultValue: "Optional"),
                                style: .inlineMultiline(min: 1, max: 4)
                            )
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .onAppear {
            if let depositInfo = account.depositInfo {
                rateText = AmountInputFormatting.bindingString(for: depositInfo.interestRateAnnual)
            }
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
            initialPrincipal: Decimal(1000000),
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
