//
//  DepositEditView.swift
//  Tenra
//
//  View for creating and editing deposits
//

import SwiftUI

struct DepositEditView: View {
    let depositsViewModel: DepositsViewModel
    let account: Account?
    let onSave: (Account) -> Void
    /// Optional toolbar action — when set (editing an existing deposit), shows a
    /// "Link interest payments" button that closes this sheet and opens the link view.
    var onLinkPayments: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var principalBalanceText: String = ""
    @State private var currency: String = "KZT"
    @State private var selectedIconSource: IconSource? = nil
    @State private var interestRateText: String = ""
    @State private var interestPostingDay: Int = 1
    @State private var capitalizationEnabled: Bool = true

    /// True when converting a regular account → deposit (account exists but has no depositInfo)
    private var isConverting: Bool {
        account != nil && account?.depositInfo == nil
    }

    var body: some View {
        EditSheetContainer(
            title: isConverting ? String(localized: "deposit.convertTitle", defaultValue: "Convert to Deposit") : (account == nil ? String(localized: "deposit.new") : String(localized: "deposit.editTitle")),
            isSaveDisabled: name.isEmpty || bankName.isEmpty || principalBalanceText.isEmpty || interestRateText.isEmpty,
            wrapInForm: false,
            onSave: saveDeposit,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Hero Section: Icon, Name, Balance, Currency
                    EditableHeroSection(
                        iconSource: $selectedIconSource,
                        title: $name,
                        balance: $principalBalanceText,
                        currency: $currency,
                        titlePlaceholder: String(localized: "deposit.namePlaceholder"),
                        config: .accountHero
                    )

                    // Bank name + interest rate grouped in one card
                    FormSection(header: String(localized: "deposit.bankDetails", defaultValue: "Bank & Rate")) {
                        UniversalRow(
                            leadingIcon: .sfSymbol("building.columns", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "deposit.bank")
                        ) {
                            FormTextField(
                                text: $bankName,
                                placeholder: String(localized: "deposit.bankNamePlaceholder"),
                                style: .inline
                            )
                        }

                        Divider()

                        UniversalRow(
                            leadingIcon: .sfSymbol("percent", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "deposit.interestRate")
                        ) {
                            FormTextField(
                                text: $interestRateText,
                                placeholder: "0.0",
                                style: .inline,
                                keyboardType: .decimalPad
                            )
                        }
                    }

                    // Posting day + capitalization grouped in one card
                    FormSection(header: String(localized: "deposit.schedule", defaultValue: "Schedule")) {
                        UniversalRow(
                            leadingIcon: .sfSymbol("calendar.badge.clock", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "deposit.dayOfMonth")
                        ) {
                            HStack(spacing: AppSpacing.sm) {
                                Text("\(interestPostingDay)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(minWidth: 28, alignment: .trailing)
                                Stepper("", value: $interestPostingDay, in: 1...31)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }

                        Divider()

                        UniversalRow(
                            leadingIcon: .sfSymbol("arrow.triangle.2.circlepath", color: AppColors.accent, size: AppIconSize.lg),
                            hint: String(localized: "deposit.capitalizationHint"),
                            title: String(localized: "deposit.enableCapitalization")
                        ) {
                            Toggle("", isOn: $capitalizationEnabled)
                                .labelsHidden()
                        }
                    }
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
            }
            .toolbar {
                // Merges with EditSheetContainer's xmark/checkmark toolbar.
                if let onLinkPayments, account?.depositInfo != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onLinkPayments) {
                            Image(systemName: "link.badge.plus")
                        }
                        .accessibilityLabel(String(localized: "deposit.linkInterest.title", defaultValue: "Link Interest Payments"))
                    }
                }
            }
        }
        .onAppear {
            if let account = account, let depositInfo = account.depositInfo {
                // Editing existing deposit
                name = account.name
                bankName = depositInfo.bankName
                principalBalanceText = AmountInputFormatting.bindingString(for: Decimal(account.balance))
                currency = account.currency
                selectedIconSource = account.iconSource
                interestRateText = AmountInputFormatting.bindingString(for: depositInfo.interestRateAnnual)
                interestPostingDay = depositInfo.interestPostingDay
                capitalizationEnabled = depositInfo.capitalizationEnabled
            } else if let account = account {
                // Converting regular account → deposit: pre-fill from account
                name = account.name
                currency = account.currency
                selectedIconSource = account.iconSource
                principalBalanceText = AmountInputFormatting.bindingString(for: account.balance)
            } else {
                // New deposit
                currency = "KZT"
                selectedIconSource = nil
                principalBalanceText = ""
                interestRateText = ""
                interestPostingDay = 1
                capitalizationEnabled = true
            }
        }
    }
}

// MARK: - Save

extension DepositEditView {
    private func saveDeposit() {
        guard let principalBalance = AmountFormatter.parse(principalBalanceText),
              let interestRate = AmountFormatter.parse(interestRateText) else {
            return
        }

        // When editing, preserve accumulated state (rate history, accruals, etc.)
        let existingInfo = account?.depositInfo

        // For conversion (or new deposit): set lastInterestCalculationDate
        // to the most recent posting day so interest accumulates correctly.
        let lastCalcDate: String?
        let lastPostingMonth: String?
        if let existing = existingInfo {
            lastCalcDate = existing.lastInterestCalculationDate
            lastPostingMonth = existing.lastInterestPostingMonth
        } else {
            let (calcDate, postMonth) = Self.computeInitialDates(postingDay: interestPostingDay)
            lastCalcDate = calcDate
            lastPostingMonth = postMonth
        }

        let depositInfo = DepositInfo(
            bankName: bankName,
            initialPrincipal: existingInfo?.initialPrincipal ?? principalBalance,
            capitalizationEnabled: capitalizationEnabled,
            interestRateAnnual: interestRate,
            interestRateHistory: existingInfo?.interestRateHistory,
            interestPostingDay: interestPostingDay,
            lastInterestCalculationDate: lastCalcDate,
            lastInterestPostingMonth: lastPostingMonth,
            interestAccruedForCurrentPeriod: existingInfo?.interestAccruedForCurrentPeriod ?? 0,
            startDate: existingInfo?.startDate,
            // Preserve the conversion marker across edits of an already-converted deposit;
            // losing it would re-expose the inherited history to the recalc sum. For a fresh
            // conversion existingInfo is nil here — AccountsViewModel.updateDeposit stamps it.
            conversionTimestamp: existingInfo?.conversionTimestamp
        )

        let balance = NSDecimalNumber(decimal: principalBalance).doubleValue
        let newAccount = Account(
            id: account?.id ?? UUID().uuidString,
            name: name,
            currency: currency,
            iconSource: selectedIconSource,
            depositInfo: depositInfo,
            shouldCalculateFromTransactions: false,
            initialBalance: balance,
            order: account?.order
        )
        HapticManager.success()
        onSave(newAccount)
    }
}

// MARK: - Helpers

extension DepositEditView {
    /// Compute initial dates for a new/converted deposit based on posting day.
    /// Returns (lastInterestCalculationDate, lastInterestPostingMonth).
    /// E.g. postingDay=3, today=March 5 → calcDate="2026-03-03", postMonth="2026-03-01"
    /// E.g. postingDay=20, today=March 5 → calcDate="2026-02-20", postMonth="2026-02-01"
    static func computeInitialDates(postingDay: Int) -> (String, String) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build this month's posting date
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = min(postingDay, calendar.range(of: .day, in: .month, for: today)?.upperBound.advanced(by: -1) ?? postingDay)
        let thisMonthPosting = calendar.date(from: components) ?? today

        let postingDate: Date
        if thisMonthPosting <= today {
            // Posting day already passed this month — use this month's posting date
            postingDate = thisMonthPosting
        } else {
            // Posting day hasn't arrived yet — use last month's posting date
            if let prevMonth = calendar.date(byAdding: .month, value: -1, to: today) {
                var prevComponents = calendar.dateComponents([.year, .month], from: prevMonth)
                let lastDay = calendar.range(of: .day, in: .month, for: prevMonth)?.upperBound.advanced(by: -1) ?? postingDay
                prevComponents.day = min(postingDay, lastDay)
                postingDate = calendar.date(from: prevComponents) ?? today
            } else {
                postingDate = today
            }
        }

        let calcDate = DateFormatters.dateFormatter.string(from: postingDate)

        // lastInterestPostingMonth = start of the month containing postingDate
        let monthComponents = calendar.dateComponents([.year, .month], from: postingDate)
        let monthStart = calendar.date(from: monthComponents) ?? postingDate
        let postMonth = DateFormatters.dateFormatter.string(from: monthStart)

        return (calcDate, postMonth)
    }
}

// MARK: - Previews

#Preview("Deposit Edit View - New") {
    let coordinator = AppCoordinator()
    NavigationStack {
        DepositEditView(
            depositsViewModel: coordinator.depositsViewModel,
            account: nil,
            onSave: { _ in }
        )
    }
}

#Preview("Deposit Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "test",
        name: "Halyk Deposit",
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

    NavigationStack {
        DepositEditView(
            depositsViewModel: coordinator.depositsViewModel,
            account: sampleAccount,
            onSave: { _ in }
        )
    }
}
