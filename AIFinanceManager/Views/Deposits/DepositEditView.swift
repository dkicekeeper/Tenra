//
//  DepositEditView.swift
//  AIFinanceManager
//
//  View for creating and editing deposits
//

import SwiftUI

struct DepositEditView: View {
    let depositsViewModel: DepositsViewModel
    let account: Account?
    let onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var principalBalanceText: String = ""
    @State private var currency: String = "KZT"
    @State private var selectedIconSource: IconSource? = nil
    @State private var interestRateText: String = ""
    @State private var interestPostingDay: Int = 1
    @State private var capitalizationEnabled: Bool = true
    @State private var showingIconPicker = false
    @FocusState private var isNameFocused: Bool

    private let depositCurrencies = ["KZT", "USD", "EUR"]

    /// True when converting a regular account → deposit (account exists but has no depositInfo)
    private var isConverting: Bool {
        account != nil && account?.depositInfo == nil
    }

    var body: some View {
        EditSheetContainer(
            title: isConverting ? String(localized: "deposit.convertTitle", defaultValue: "Convert to Deposit") : (account == nil ? String(localized: "deposit.new") : String(localized: "deposit.editTitle")),
            isSaveDisabled: name.isEmpty || bankName.isEmpty || principalBalanceText.isEmpty || interestRateText.isEmpty,
            onSave: {
                guard let principalBalance = AmountFormatter.parse(principalBalanceText),
                      let interestRate = AmountFormatter.parse(interestRateText) else {
                    return
                }

                // When editing, preserve accumulated state (rate history, accruals, etc.)
                let existingInfo = account?.depositInfo

                // For conversion (or new deposit): set lastInterestCalculationDate
                // to the most recent posting day so interest accumulates correctly.
                // E.g. posting day = 3, today = March 5 → lastCalcDate = March 3 → shows 2 days interest.
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
                    principalBalance: principalBalance,
                    capitalizationEnabled: capitalizationEnabled,
                    interestAccruedNotCapitalized: existingInfo?.interestAccruedNotCapitalized ?? 0,
                    interestRateAnnual: interestRate,
                    interestRateHistory: existingInfo?.interestRateHistory,
                    interestPostingDay: interestPostingDay,
                    lastInterestCalculationDate: lastCalcDate,
                    lastInterestPostingMonth: lastPostingMonth,
                    interestAccruedForCurrentPeriod: existingInfo?.interestAccruedForCurrentPeriod ?? 0
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
            },
            onCancel: { dismiss() }
        ) {
            Section(header: Text(String(localized: "deposit.name"))) {
                TextField(String(localized: "deposit.namePlaceholder"), text: $name)
                    .focused($isNameFocused)
            }

            Section(header: Text(String(localized: "deposit.bank"))) {
                TextField(String(localized: "deposit.bankNamePlaceholder"), text: $bankName)

                Button {
                    HapticManager.light()
                    showingIconPicker = true
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Text(String(localized: "iconPicker.title"))
                        Spacer()
                        IconView(
                            source: selectedIconSource,
                            size: AppIconSize.lg
                        )
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(AppTypography.caption)
                    }
                }
            }

            Section(header: Text(String(localized: "common.currency"))) {
                Picker(String(localized: "common.currency"), selection: $currency) {
                    ForEach(depositCurrencies, id: \.self) { curr in
                        Text("\(Formatting.currencySymbol(for: curr)) \(curr)").tag(curr)
                    }
                }
            }

            Section(header: Text(String(localized: "deposit.initialAmount"))) {
                TextField(String(localized: "common.balancePlaceholder"), text: $principalBalanceText)
                    .keyboardType(.decimalPad)
            }

            Section(header: Text(String(localized: "deposit.interestRate"))) {
                HStack {
                    TextField("0.0", text: $interestRateText)
                        .keyboardType(.decimalPad)
                    Text(String(localized: "deposit.rateAnnual"))
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(String(localized: "deposit.postingDayTitle"))) {
                Picker(String(localized: "deposit.dayOfMonth"), selection: $interestPostingDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                Text(String(localized: "deposit.postingDayHint"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(String(localized: "deposit.capitalizationTitle"))) {
                Toggle(String(localized: "deposit.enableCapitalization"), isOn: $capitalizationEnabled)
                Text(String(localized: "deposit.capitalizationHint"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if let account = account, let depositInfo = account.depositInfo {
                // Editing existing deposit
                name = account.name
                bankName = depositInfo.bankName
                principalBalanceText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue)
                currency = account.currency
                selectedIconSource = account.iconSource
                interestRateText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.interestRateAnnual).doubleValue)
                interestPostingDay = depositInfo.interestPostingDay
                capitalizationEnabled = depositInfo.capitalizationEnabled
            } else if let account = account {
                // Converting regular account → deposit: pre-fill from account
                name = account.name
                currency = account.currency
                selectedIconSource = account.iconSource
                principalBalanceText = String(format: "%.2f", account.balance)
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
        .task {
            // One MainActor tick is sufficient for @FocusState after layout
            guard account == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $selectedIconSource)
        }
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
        iconSource: .bankLogo(.halykBank),
        depositInfo: DepositInfo(
            bankName: "Halyk Bank",
            principalBalance: Decimal(1000000),
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
