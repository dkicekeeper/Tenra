//
//  TransactionCardView.swift
//  Tenra
//
//  Pure-UI transaction row. No @Environment, no @State, no sheets, no swipe actions.
//  All business logic (recurring-badge resolution, subscription icon lookup, subcategory
//  links, delete/stop/resume, edit sheet) lives in `TransactionCard` which wraps this view.
//
//  Use this component directly when you need the visual only — read-only lists, selection
//  UIs (LinkPaymentsView), voice-input previews, design-system previews.
//

import SwiftUI

struct TransactionCardView: View {
    let transaction: Transaction
    let currency: String
    let styleData: CategoryStyleData
    let sourceAccount: Account?
    let targetAccount: Account?
    /// Pre-resolved subscription icon (caller looks up `RecurringSeries.iconSource` if needed).
    let subscriptionIconSource: IconSource?
    /// Pre-resolved recurring-badge flag (caller decides based on `isFuture` + `series.isActive`).
    let showRecurringBadge: Bool
    /// Pre-resolved subcategory links (caller resolves via `categoriesViewModel`).
    let linkedSubcategories: [Subcategory]

    init(
        transaction: Transaction,
        currency: String,
        styleData: CategoryStyleData,
        sourceAccount: Account? = nil,
        targetAccount: Account? = nil,
        subscriptionIconSource: IconSource? = nil,
        showRecurringBadge: Bool = false,
        linkedSubcategories: [Subcategory] = []
    ) {
        self.transaction = transaction
        self.currency = currency
        self.styleData = styleData
        self.sourceAccount = sourceAccount
        self.targetAccount = targetAccount
        self.subscriptionIconSource = subscriptionIconSource
        self.showRecurringBadge = showRecurringBadge
        self.linkedSubcategories = linkedSubcategories
    }

    private var resolvedAccounts: [Account] {
        [sourceAccount, targetAccount].compactMap { $0 }
    }

    private var isFutureDate: Bool {
        TransactionDisplayHelper.isFutureDate(transaction.date)
    }

    private var amountColor: Color {
        TransactionDisplayHelper.amountColor(for: transaction.type)
    }

    private var amountPrefix: String {
        TransactionDisplayHelper.amountPrefix(for: transaction.type)
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            TransactionIconView(
                transaction: transaction,
                styleData: styleData,
                subscriptionIconSource: subscriptionIconSource,
                showRecurringBadge: showRecurringBadge
            )

            TransactionInfoView(
                transaction: transaction,
                accounts: resolvedAccounts,
                linkedSubcategories: linkedSubcategories
            )

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if transaction.type == .internalTransfer {
                    TransferAmountView(
                        transaction: transaction,
                        sourceAccount: sourceAccount,
                        targetAccount: targetAccount,
                        depositAccountId: nil
                    )
                } else {
                    FormattedAmountView(
                        amount: transaction.amount,
                        currency: transaction.currency,
                        prefix: amountPrefix,
                        color: amountColor
                    )

                    if let targetCurrency = transaction.targetCurrency,
                       let targetAmount = transaction.targetAmount,
                       targetCurrency != transaction.currency {
                        FormattedAmountView(
                            amount: targetAmount,
                            currency: targetCurrency,
                            prefix: "",
                            color: amountColor.opacity(0.7)
                        )
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.compact)
        .futureTransactionStyle(isFuture: isFutureDate)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(TransactionDisplayHelper.accessibilityText(for: transaction, accounts: resolvedAccounts))
    }
}


// MARK: - Previews

private enum TransactionCardPreviewFactory {
    static let kaspi = Account(id: "acc-kaspi", name: "Kaspi Gold", currency: "KZT",
                               iconSource: .brandService("kaspi.kz"), initialBalance: 150_000)
    static let halyk = Account(id: "acc-halyk", name: "Halyk Bank", currency: "KZT",
                               iconSource: .brandService("halykbank.kz"), initialBalance: 500_000)
    static let deposit = Account(id: "acc-deposit", name: "Halyk Deposit", currency: "KZT",
                                 iconSource: .sfSymbol("lock.fill"), initialBalance: 1_000_000)
    static let loan = Account(id: "acc-loan", name: "Kaspi Loan", currency: "KZT",
                              iconSource: .sfSymbol("building.columns"), initialBalance: -500_000)

    static func today() -> String { DateFormatters.dateFormatter.string(from: Date()) }
    static func future(_ days: Int) -> String {
        DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        )
    }

    static func style(for tx: Transaction) -> CategoryStyleData {
        CategoryStyleHelper.cached(category: tx.category, type: tx.type, customCategories: [])
    }
}

#Preview("Expense") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-exp", date: f.today(), description: "Кофе",
                         amount: 2_500, currency: "KZT", type: .expense,
                         category: "Food", accountId: f.kaspi.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.kaspi
    )
    .padding()
}

#Preview("Expense + Subcategories") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-exp-sub", date: f.today(), description: "Magnum",
                         amount: 18_500, currency: "KZT", type: .expense,
                         category: "Groceries", accountId: f.kaspi.id)
    let subs = [
        Subcategory(name: "Овощи"),
        Subcategory(name: "Мясо"),
        Subcategory(name: "Хлеб")
    ]
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.kaspi,
        linkedSubcategories: subs
    )
    .padding()
}

#Preview("Income") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-inc", date: f.today(), description: "Зарплата",
                         amount: 450_000, currency: "KZT", type: .income,
                         category: "Salary", accountId: f.halyk.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.halyk
    )
    .padding()
}

#Preview("Income — Multi-currency") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-inc-mc", date: f.today(), description: "Freelance",
                         amount: 500, currency: "USD", type: .income,
                         category: "Freelance", accountId: f.halyk.id,
                         targetCurrency: "KZT", targetAmount: 240_000)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.halyk
    )
    .padding()
}

#Preview("Internal Transfer") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-tr", date: f.today(), description: "Перевод",
                         amount: 50_000, currency: "KZT", type: .internalTransfer,
                         category: "Transfer",
                         accountId: f.kaspi.id, targetAccountId: f.halyk.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.kaspi, targetAccount: f.halyk
    )
    .padding()
}

#Preview("Subscription — Future + Recurring Badge") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-sub", date: f.future(3), description: "Netflix",
                         amount: 4_990, currency: "KZT", type: .expense,
                         category: "Subscriptions", accountId: f.kaspi.id,
                         recurringSeriesId: "series-netflix")
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.kaspi,
        subscriptionIconSource: .brandService("netflix.com"),
        showRecurringBadge: true
    )
    .padding()
}

#Preview("Deposit Top-Up") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-dep-up", date: f.today(), description: "Пополнение депозита",
                         amount: 200_000, currency: "KZT", type: .depositTopUp,
                         category: "Deposit", accountId: f.deposit.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.deposit
    )
    .padding()
}

#Preview("Deposit Withdrawal") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-dep-w", date: f.today(), description: "Снятие с депозита",
                         amount: 75_000, currency: "KZT", type: .depositWithdrawal,
                         category: "Deposit", accountId: f.deposit.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.deposit
    )
    .padding()
}

#Preview("Deposit Interest Accrual") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "di_preview", date: f.today(), description: "Начисление процентов",
                         amount: 12_345, currency: "KZT", type: .depositInterestAccrual,
                         category: "Interest", accountId: f.deposit.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.deposit
    )
    .padding()
}

#Preview("Loan Payment") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-loan-pay", date: f.today(), description: "Платёж по кредиту",
                         amount: 42_500, currency: "KZT", type: .loanPayment,
                         category: "Loan", accountId: f.loan.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.loan
    )
    .padding()
}

#Preview("Loan Early Repayment") {
    let f = TransactionCardPreviewFactory.self
    let tx = Transaction(id: "p-loan-er", date: f.today(), description: "Досрочное погашение",
                         amount: 100_000, currency: "KZT", type: .loanEarlyRepayment,
                         category: "Loan", accountId: f.loan.id)
    TransactionCardView(
        transaction: tx, currency: "KZT", styleData: f.style(for: tx),
        sourceAccount: f.loan
    )
    .padding()
}

#Preview("All Types — Stacked") {
    let f = TransactionCardPreviewFactory.self
    let txs: [(Transaction, IconSource?, Bool, [Subcategory])] = [
        (Transaction(id: "s1", date: f.today(), description: "Magnum",
                     amount: 18_500, currency: "KZT", type: .expense,
                     category: "Groceries", accountId: f.kaspi.id),
         nil, false, [Subcategory(name: "Овощи"), Subcategory(name: "Мясо")]),
        (Transaction(id: "s2", date: f.today(), description: "Зарплата",
                     amount: 450_000, currency: "KZT", type: .income,
                     category: "Salary", accountId: f.halyk.id),
         nil, false, []),
        (Transaction(id: "s3", date: f.today(), description: "Перевод",
                     amount: 50_000, currency: "KZT", type: .internalTransfer,
                     category: "Transfer",
                     accountId: f.kaspi.id, targetAccountId: f.halyk.id),
         nil, false, []),
        (Transaction(id: "s4", date: f.future(5), description: "Spotify",
                     amount: 1_490, currency: "KZT", type: .expense,
                     category: "Subscriptions", accountId: f.kaspi.id,
                     recurringSeriesId: "s-spotify"),
         .brandService("spotify.com"), true, []),
        (Transaction(id: "s5", date: f.today(), description: "Начисление %",
                     amount: 12_345, currency: "KZT", type: .depositInterestAccrual,
                     category: "Interest", accountId: f.deposit.id),
         nil, false, []),
        (Transaction(id: "s6", date: f.today(), description: "Платёж",
                     amount: 42_500, currency: "KZT", type: .loanPayment,
                     category: "Loan", accountId: f.loan.id),
         nil, false, [])
    ]
    let accountsById = Dictionary(uniqueKeysWithValues:
        [f.kaspi, f.halyk, f.deposit, f.loan].map { ($0.id, $0) })

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            ForEach(Array(txs.enumerated()), id: \.offset) { _, entry in
                let (tx, iconSrc, badge, subs) = entry
                TransactionCardView(
                    transaction: tx,
                    currency: "KZT",
                    styleData: f.style(for: tx),
                    sourceAccount: tx.accountId.flatMap { accountsById[$0] },
                    targetAccount: tx.targetAccountId.flatMap { accountsById[$0] },
                    subscriptionIconSource: iconSrc,
                    showRecurringBadge: badge,
                    linkedSubcategories: subs
                )
            }
        }
        .padding()
    }
}
