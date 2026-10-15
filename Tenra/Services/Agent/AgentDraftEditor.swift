//
//  AgentDraftEditor.swift
//  Tenra
//
//  Changing an income or an expense of a draft before it is saved (docs/plan-ai-assistant.md
//  §1, "Сделать": Save or edit). The confirm card opens the voice confirmation form on the
//  operation; what comes back is resolved again by `TransactionDraftService.makeDraft`, the path
//  the draft came from, so the edited operation is exactly what Save writes. The account and the
//  category were picked on the form: they are no longer guesses.
//

import Foundation

enum AgentDraftEditor {
    /// The draft as the form's input.
    static func operation(from draft: TransactionDraft, subcategories: [Subcategory]) -> ParsedOperation {
        ParsedOperation(
            type: draft.type,
            amount: Decimal(string: String(draft.amount)) ?? Decimal(draft.amount),
            currencyCode: draft.currency,
            date: draft.date,
            accountId: draft.accountId,
            categoryName: draft.categoryName.isEmpty ? nil : draft.categoryName,
            subcategoryNames: subcategories.filter { draft.subcategoryIds.contains($0.id) }.map(\.name),
            note: draft.note
        )
    }

    /// What the form returned, as the draft Save writes. A rate missing from the cache is
    /// fetched once: the person is in the app, as for the toolkit's drafts.
    static func draft(
        from operation: ParsedOperation,
        accounts: [Account],
        categories: [CustomCategory],
        subcategories: [Subcategory],
        learned: VoiceLearningStore,
        convert: (Double, String, String) async -> Double?
    ) async -> Result<TransactionDraft, DraftIssue> {
        func resolve(_ conversion: ConversionPolicy) -> Result<TransactionDraft, DraftIssue> {
            TransactionDraftService.makeDraft(
                from: operation,
                accounts: accounts,
                categories: categories,
                learned: learned,
                conversion: conversion
            )
        }
        var result = resolve(.cachedOnly)
        if case .failure(.needsFXConversion(let amount, let from, let to)) = result {
            result = resolve(.provided(await convert(amount, from, to)))
        }
        return result.map { draft in
            var draft = draft
            draft.subcategoryIds = subcategories
                .filter { operation.subcategoryNames.contains($0.name) }
                .map(\.id)
            return draft
        }
    }

    /// Why the form's operation could not become a draft, in the form's own words.
    static func message(for issue: DraftIssue) -> String {
        switch issue {
        case .missingAmount: String(localized: "voiceConfirmation.warning.enterValidAmount")
        case .noEligibleAccount: String(localized: "voiceConfirmation.warning.selectAccount")
        case .needsFXConversion: String(localized: "currency.error.conversionFailed")
        }
    }
}
