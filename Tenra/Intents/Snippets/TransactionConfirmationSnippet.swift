//
//  TransactionConfirmationSnippet.swift
//  Tenra
//
//  Shown before an intent commits. Every guessed field is marked, which is what
//  makes it acceptable for the resolver to guess at all.
//

import SwiftUI

struct TransactionConfirmationSnippet: View {

    let draft: TransactionDraft
    let accountName: String

    private var categoryWasGuessed: Bool {
        draft.warnings.contains { warning in
            if case .categorySubstituted = warning { return true }
            return false
        }
    }

    private var accountWasGuessed: Bool {
        draft.warnings.contains(.accountInferred)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormattedAmountText(
                amount: draft.amount,
                currency: draft.currency,
                fontSize: .title2,
                fontWeight: .semibold
            )

            row(
                label: String(localized: "intent.snippet.category"),
                // Empty means "uncategorized", which is a valid outcome; show a
                // readable placeholder rather than a blank row.
                value: draft.categoryName.isEmpty
                    ? String(localized: "intent.snippet.noCategory")
                    : draft.categoryName,
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
