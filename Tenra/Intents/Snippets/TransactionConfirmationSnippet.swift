//
//  TransactionConfirmationSnippet.swift
//  Tenra
//
//  Shown before an intent commits. Every guessed field is marked, which is what
//  makes it acceptable for the resolver to guess at all.
//

import SwiftUI

struct TransactionConfirmationSnippet: View {

    // Plain display fields rather than the draft itself: `TransactionConfirmationSnippetIntent`
    // rebuilds this card from its own `@Parameter`s (a SnippetIntent may be re-run by the
    // system at any time) and has no `TransactionDraft` to hand over.
    let amount: Double
    let currency: String
    let categoryName: String
    let accountName: String
    let categoryWasGuessed: Bool
    let accountWasGuessed: Bool

    init(
        amount: Double,
        currency: String,
        categoryName: String,
        accountName: String,
        categoryWasGuessed: Bool,
        accountWasGuessed: Bool
    ) {
        self.amount = amount
        self.currency = currency
        self.categoryName = categoryName
        self.accountName = accountName
        self.categoryWasGuessed = categoryWasGuessed
        self.accountWasGuessed = accountWasGuessed
    }

    /// Convenience path for callers that already hold the resolved draft.
    init(draft: TransactionDraft, accountName: String) {
        self.init(
            amount: draft.amount,
            currency: draft.currency,
            categoryName: draft.categoryName,
            accountName: accountName,
            categoryWasGuessed: draft.warnings.contains { warning in
                if case .categorySubstituted = warning { return true }
                return false
            },
            accountWasGuessed: draft.warnings.contains(.accountInferred)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: .title2,
                fontWeight: .semibold
            )

            row(
                label: String(localized: "intent.snippet.category"),
                // Empty means "uncategorized", which is a valid outcome; show a
                // readable placeholder rather than a blank row.
                value: categoryName.isEmpty
                    ? String(localized: "intent.snippet.noCategory")
                    : categoryName,
                guessed: categoryWasGuessed
            )

            row(
                label: String(localized: "intent.snippet.account"),
                value: accountName,
                guessed: accountWasGuessed
            )
        }
        // The snippet container hands the view the full card width; without
        // this the VStack hugs its content and gets centred.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
    }

    private func row(label: String, value: String, guessed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: AppSpacing.md)

            // The "guessed" marker is its own line rather than part of the
            // value: appended inline it wrapped mid-phrase, so a two-word
            // category read as two ragged lines.
            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(value)
                    .multilineTextAlignment(.trailing)

                if guessed {
                    Text(String(localized: "intent.snippet.guessed"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }
}
