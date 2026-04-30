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
    @FocusState private var isRateFocused: Bool

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
                            config: .standard,
                            leadingIcon: .sfSymbol("percent", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "deposit.newRate"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField("0.0", text: $rateText)
                                    .inlineFieldStyle(keyboard: .decimalPad, maxWidth: 80)
                                    .focused($isRateFocused)
                                Text(String(localized: "deposit.rateAnnual"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "deposit.effectiveDate"),
                            selection: $effectiveFromDate
                        )

                        Divider().padding(.leading, AppSpacing.lg)

                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("note.text", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "deposit.note"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.notePlaceholder", defaultValue: "Optional"),
                                text: $noteText,
                                axis: .vertical
                            )
                            .inlineNoteStyle()
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
