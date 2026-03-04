//
//  TransactionCardComponents.swift
//  AIFinanceManager
//
//  Extracted components from TransactionCard for better modularity
//

import SwiftUI

// MARK: - Transaction Icon View

struct TransactionIconView: View {
    let transaction: Transaction
    let styleData: CategoryStyleData
    /// Icon source from the related subscription series (if any)
    var subscriptionIconSource: IconSource? = nil
    /// Show the arrow.clockwise badge in the top-left corner.
    /// Should be true only for future transactions whose recurring series is still active.
    var showRecurringBadge: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main icon: subscription logo or category icon
            if let iconSource = subscriptionIconSource {
                IconView(
                    source: iconSource,
                    style: .circle(
                        size: AppIconSize.xxl,
                        tint: .original,
                        backgroundColor: styleData.lightBackgroundColor
                    )
                )
            } else {
                IconView(
                    source: .sfSymbol(styleData.iconName),
                    style: .circle(
                        size: AppIconSize.xxl,
                        tint: .monochrome(transaction.type == .internalTransfer ? AppColors.transfer : styleData.primaryColor),
                        backgroundColor: transaction.type == .internalTransfer ? AppColors.transfer.opacity(0.2) : styleData.lightBackgroundColor
                    )
                )
            }

            // Recurring badge — top-left corner (future + active series only)
            if showRecurringBadge {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: AppIconSize.sm))
                    .foregroundStyle(.primary)
                    .padding(AppSpacing.xs)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(Circle())
                    .offset(x: -8, y: -8)
            }
        }
    }
}

// MARK: - Transaction Info View

struct TransactionInfoView: View {
    let transaction: Transaction
    let accounts: [Account]
    let linkedSubcategories: [Subcategory]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Category name
            Text(transaction.type == .internalTransfer
                 ? String(localized: "transactionType.transfer")
                 : transaction.category)
                .font(AppTypography.h4)
            
            // Subcategories
            if !linkedSubcategories.isEmpty {
                Text(linkedSubcategories.map { $0.name }.joined(separator: ", "))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.primary)
            }
            
            // Account info or transfer info
            if transaction.type == .internalTransfer {
                TransferAccountInfo(transaction: transaction, accounts: accounts)
            } else {
                RegularAccountInfo(transaction: transaction, accounts: accounts)
            }
            
            // Description
            if !transaction.description.isEmpty {
                Text(transaction.description)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Transfer Account Info

struct TransferAccountInfo: View {
    let transaction: Transaction
    let accounts: [Account]

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            // Source account
            if let sourceId = transaction.accountId,
               let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                // Account exists - show with logo
                HStack(spacing: AppSpacing.xs) {
                    IconView(source: sourceAccount.iconSource, size: AppIconSize.sm)
                    Text(sourceAccount.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
            } else if let accountName = transaction.accountName {
                // Account was deleted - show name only
                Text(accountName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Image(systemName: "arrow.right")
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(.secondary)

            // Target account
            if let targetId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetId }) {
                // Account exists - show with logo
                HStack(spacing: AppSpacing.xs) {
                    IconView(source: targetAccount.iconSource, size: AppIconSize.sm)
                    Text(targetAccount.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
            } else if let targetAccountName = transaction.targetAccountName {
                // Account was deleted - show name only
                Text(targetAccountName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - Regular Account Info

struct RegularAccountInfo: View {
    let transaction: Transaction
    let accounts: [Account]

    var body: some View {
        if let accountId = transaction.accountId,
           let account = accounts.first(where: { $0.id == accountId }) {
            // Account exists - show with logo
            HStack(spacing: AppSpacing.xs) {
                IconView(source: account.iconSource, size: AppIconSize.sm)
                Text(account.name)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        } else if let accountName = transaction.accountName {
            // Account was deleted - show name only without logo
            Text(accountName)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}

// MARK: - Preview Helpers

private extension Transaction {
    static func preview(
        id: String = UUID().uuidString,
        date: String = DateFormatters.dateFormatter.string(from: Date()),
        description: String = "",
        amount: Double = 1000,
        currency: String = "KZT",
        type: TransactionType = .expense,
        category: String = "Food",
        accountId: String? = nil,
        targetAccountId: String? = nil,
        accountName: String? = nil,
        targetAccountName: String? = nil,
        recurringSeriesId: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: accountName,
            targetAccountName: targetAccountName,
            recurringSeriesId: recurringSeriesId
        )
    }
}

private extension Account {
    static func preview(
        id: String = UUID().uuidString,
        name: String,
        currency: String = "KZT",
        iconSource: IconSource? = nil
    ) -> Account {
        Account(id: id, name: name, currency: currency, iconSource: iconSource)
    }
}

// MARK: - TransactionIconView Previews

#Preview("Icon — Expense categories") {
    let categories = ["Food", "Transport", "Health", "Shopping", "Entertainment", "Education"]
    let types: [TransactionType] = [.expense, .expense, .expense, .expense, .expense, .expense]

    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: AppSpacing.lg) {
            ForEach(Array(zip(categories, types)), id: \.0) { category, type in
                VStack(spacing: AppSpacing.sm) {
                    TransactionIconView(
                        transaction: .preview(type: type, category: category),
                        styleData: CategoryStyleHelper.cached(category: category, type: type, customCategories: [])
                    )
                    Text(category)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

#Preview("Icon — Income") {
    HStack(spacing: AppSpacing.xl) {
        VStack(spacing: AppSpacing.sm) {
            TransactionIconView(
                transaction: .preview(type: .income, category: "Salary"),
                styleData: CategoryStyleHelper.cached(category: "Salary", type: .income, customCategories: [])
            )
            Text("Salary").font(AppTypography.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: AppSpacing.sm) {
            TransactionIconView(
                transaction: .preview(type: .income, category: "Freelance"),
                styleData: CategoryStyleHelper.cached(category: "Freelance", type: .income, customCategories: [])
            )
            Text("Freelance").font(AppTypography.caption).foregroundStyle(.secondary)
        }
    }
    .padding()
}

#Preview("Icon — Internal Transfer") {
    VStack(spacing: AppSpacing.sm) {
        TransactionIconView(
            transaction: .preview(type: .internalTransfer, category: "Transfer"),
            styleData: CategoryStyleHelper.cached(category: "Transfer", type: .internalTransfer, customCategories: [])
        )
        Text("Transfer").font(AppTypography.caption).foregroundStyle(.secondary)
    }
    .padding()
}

#Preview("Icon — Recurring badge") {
    HStack(spacing: AppSpacing.xl) {
        VStack(spacing: AppSpacing.sm) {
            TransactionIconView(
                transaction: .preview(type: .expense, category: "Subscriptions", recurringSeriesId: nil),
                styleData: CategoryStyleHelper.cached(category: "Subscriptions", type: .expense, customCategories: [])
            )
            Text("No badge").font(AppTypography.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: AppSpacing.sm) {
            TransactionIconView(
                transaction: .preview(type: .expense, category: "Subscriptions", recurringSeriesId: "series-1"),
                styleData: CategoryStyleHelper.cached(category: "Subscriptions", type: .expense, customCategories: [])
            )
            Text("With badge").font(AppTypography.caption).foregroundStyle(.secondary)
        }
    }
    .padding()
}

#Preview("Icon — Subscription logo (brandService)") {
    HStack(spacing: AppSpacing.xl) {
        VStack(spacing: AppSpacing.sm) {
            TransactionIconView(
                transaction: .preview(type: .expense, category: "Subscriptions", recurringSeriesId: "s1"),
                styleData: CategoryStyleHelper.cached(category: "Subscriptions", type: .expense, customCategories: []),
                subscriptionIconSource: .brandService("netflix.com")
            )
            Text("Netflix").font(AppTypography.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: AppSpacing.sm) {
            TransactionIconView(
                transaction: .preview(type: .expense, category: "Subscriptions", recurringSeriesId: "s2"),
                styleData: CategoryStyleHelper.cached(category: "Subscriptions", type: .expense, customCategories: []),
                subscriptionIconSource: .sfSymbol("music.note")
            )
            Text("Music").font(AppTypography.caption).foregroundStyle(.secondary)
        }
    }
    .padding()
}

// MARK: - TransactionInfoView Previews

#Preview("Info — Expense with account") {
    let account = Account.preview(id: "acc-1", name: "Kaspi Gold", iconSource: .bankLogo(.kaspi))
    TransactionInfoView(
        transaction: .preview(
            description: "Supermarket",
            type: .expense,
            category: "Food",
            accountId: "acc-1"
        ),
        accounts: [account],
        linkedSubcategories: []
    )
    .padding()
}

#Preview("Info — With subcategories") {
    let account = Account.preview(id: "acc-1", name: "Kaspi Gold")
    let subcategories = [
        Subcategory(id: "s1", name: "Groceries"),
        Subcategory(id: "s2", name: "Vegetables")
    ]
    TransactionInfoView(
        transaction: .preview(
            description: "Weekend shopping",
            type: .expense,
            category: "Food",
            accountId: "acc-1"
        ),
        accounts: [account],
        linkedSubcategories: subcategories
    )
    .padding()
}

#Preview("Info — Deleted account fallback") {
    TransactionInfoView(
        transaction: Transaction(
            id: "t1",
            date: DateFormatters.dateFormatter.string(from: Date()),
            description: "Old transaction",
            amount: 5000,
            currency: "KZT",
            type: .expense,
            category: "Shopping",
            accountId: "deleted-id",
            accountName: "Deleted Account"
        ),
        accounts: [],   // пустой — аккаунт удалён
        linkedSubcategories: []
    )
    .padding()
}

#Preview("Info — No description, no account") {
    TransactionInfoView(
        transaction: .preview(description: "", type: .income, category: "Salary"),
        accounts: [],
        linkedSubcategories: []
    )
    .padding()
}

// MARK: - TransferAccountInfo Previews

#Preview("TransferAccountInfo — Both accounts exist") {
    let source = Account.preview(id: "src", name: "Kaspi Gold", iconSource: .bankLogo(.kaspi))
    let target = Account.preview(id: "tgt", name: "Halyk Bank", iconSource: .bankLogo(.halykBank))
    TransferAccountInfo(
        transaction: .preview(type: .internalTransfer, category: "Transfer", accountId: "src", targetAccountId: "tgt"),
        accounts: [source, target]
    )
    .padding()
}

#Preview("TransferAccountInfo — Deleted accounts (fallback)") {
    TransferAccountInfo(
        transaction: Transaction(
            id: "t1",
            date: DateFormatters.dateFormatter.string(from: Date()),
            description: "",
            amount: 10000,
            currency: "KZT",
            type: .internalTransfer,
            category: "Transfer",
            accountId: "deleted-src",
            targetAccountId: "deleted-tgt",
            accountName: "Old Account A",
            targetAccountName: "Old Account B"
        ),
        accounts: []    // оба удалены
    )
    .padding()
}

#Preview("TransferAccountInfo — One account missing") {
    let source = Account.preview(id: "src", name: "Kaspi Gold", iconSource: .bankLogo(.kaspi))
    TransferAccountInfo(
        transaction: Transaction(
            id: "t1",
            date: DateFormatters.dateFormatter.string(from: Date()),
            description: "",
            amount: 10000,
            currency: "KZT",
            type: .internalTransfer,
            category: "Transfer",
            accountId: "src",
            targetAccountId: "missing",
            targetAccountName: "Deleted Target"
        ),
        accounts: [source]
    )
    .padding()
}

// MARK: - RegularAccountInfo Previews

#Preview("RegularAccountInfo — Account exists") {
    let account = Account.preview(id: "acc-1", name: "Kaspi Gold", iconSource: .bankLogo(.kaspi))
    RegularAccountInfo(
        transaction: .preview(accountId: "acc-1"),
        accounts: [account]
    )
    .padding()
}

#Preview("RegularAccountInfo — Deleted account fallback") {
    RegularAccountInfo(
        transaction: Transaction(
            id: "t1",
            date: DateFormatters.dateFormatter.string(from: Date()),
            description: "Old payment",
            amount: 500,
            currency: "KZT",
            type: .expense,
            category: "Food",
            accountId: "deleted-id",
            accountName: "My Old Card"
        ),
        accounts: []    // аккаунт удалён
    )
    .padding()
}

#Preview("RegularAccountInfo — No account at all") {
    RegularAccountInfo(
        transaction: .preview(accountId: nil),
        accounts: []
    )
    .padding()
    .overlay { Text("(empty — nothing renders)").font(.caption).foregroundStyle(.secondary) }
}
