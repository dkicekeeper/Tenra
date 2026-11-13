//
//  FinanceToolkit+Review.swift
//  Tenra
//
//  The assistant goes through the payments on review (docs/plan-ten-agent.md stage 2): the
//  payments the Wallet and bank notification automations saved with a guessed category or
//  account (WalletCaptureStore.toReview, the To review screen of Settings).
//  `get_review_queue` reads them; `draft_review_confirm` files the ones that are right as one
//  draft, whose Save does what "Correct" does on the screen (WalletPaymentRecorder.confirm: the
//  category is remembered for the merchant, the account for the card). A wrong one is fixed
//  with `draft_transaction_edit`, whose Save confirms it too. The questions of that screen
//  (a subscription's charge, a transfer between own accounts) stay there.
//

import Foundation

/// What a confirmed payment taught, so Undo can put it back.
struct AgentReviewUndo: Equatable {
    let transactionId: String
    let merchant: String
    let previousCategoryId: String?
    let previousSubcategoryIds: [String]?
    let card: String
    let previousAccountId: String?
}

enum AgentReviewConfirm {
    /// Confirms a payment still on review, as the To review screen does. nil when the record
    /// is not a captured payment or was looked at already.
    static func confirm(
        _ transaction: Transaction,
        editedFrom previous: Transaction? = nil,
        previousSubcategoryIds: Set<String>? = nil,
        categoriesViewModel: CategoriesViewModel,
        captures: WalletCaptureStore = .shared,
        merchants: MerchantCategoryMemory = .shared,
        cards: CardAccountMemory = .shared
    ) -> AgentReviewUndo? {
        guard let capture = captures.capture(forTransactionId: transaction.id), !capture.isReviewed else { return nil }
        let categories = categoriesViewModel.customCategories
        let undo = AgentReviewUndo(
            transactionId: transaction.id,
            merchant: capture.payment.merchant,
            previousCategoryId: merchants.category(forMerchant: capture.payment.merchant, in: categories)?.id,
            previousSubcategoryIds: merchants.subcategoryIds(forMerchant: capture.payment.merchant),
            card: capture.payment.card,
            previousAccountId: cards.accountId(forCard: capture.payment.card)
        )
        WalletPaymentRecorder.confirm(
            transaction,
            subcategoryIds: categoriesViewModel.getSubcategoriesForTransaction(transaction.id).map(\.id),
            categories: categories,
            editedFrom: previous,
            previousSubcategoryIds: previousSubcategoryIds,
            captures: captures,
            merchants: merchants,
            cards: cards
        )
        return undo
    }

    /// Back on review, the merchant and the card remembered as before.
    static func undo(
        _ undo: AgentReviewUndo,
        captures: WalletCaptureStore = .shared,
        merchants: MerchantCategoryMemory = .shared,
        cards: CardAccountMemory = .shared
    ) {
        if let categoryId = undo.previousCategoryId {
            merchants.remember(categoryId: categoryId, subcategoryIds: undo.previousSubcategoryIds ?? [], forMerchant: undo.merchant)
        } else if let key = MerchantCategoryMemory.key(forMerchant: undo.merchant) {
            merchants.forget(merchantId: key)
        }
        if let accountId = undo.previousAccountId {
            cards.remember(accountId: accountId, forCard: undo.card)
        } else {
            cards.forget(card: undo.card)
        }
        captures.markUnreviewed(transactionId: undo.transactionId)
    }
}

extension FinanceToolkit {
    /// The most payments one answer lists and one draft confirms.
    static let reviewLimit = 30

    private struct ConfirmInput: Decodable {
        let transactionIds: [String]?
        let all: Bool?

        enum CodingKeys: String, CodingKey {
            case all
            case transactionIds = "transaction_ids"
        }
    }

    /// The payments with a guess nobody looked at, newest first, as records. The questions of
    /// the To review screen are counted apart.
    private func reviewQueue() -> (payments: [(capture: WalletCaptureStore.Capture, transaction: Transaction)], questions: Int) {
        var payments: [(WalletCaptureStore.Capture, Transaction)] = []
        var questions = 0
        for capture in captures.toReview {
            if capture.subscriptionSuggestion != nil || capture.ownTransfer != nil {
                questions += 1
                continue
            }
            // The index first; the list only for an id it does not know.
            guard let transaction = store.transactionById[capture.id] ?? store.transactions.first(where: { $0.id == capture.id }),
                  transaction.type == .expense || transaction.type == .income else { continue }
            payments.append((capture, transaction))
        }
        return (payments, questions)
    }

    /// `get_review_queue`: the captured payments waiting for a look, with what was guessed.
    func reviewQueueResult() -> JSONValue {
        guard store.hasCompletedInitialLoad else {
            return ["loading": true, "payments": .array([]), "total": 0]
        }
        let queue = reviewQueue()
        let payments: [JSONValue] = queue.payments.prefix(Self.reviewLimit).map { capture, transaction in
            return [
                "transaction_id": .string(transaction.id),
                "date": .string(transaction.date),
                "type": .string(transaction.type.rawValue),
                "merchant": .string(capture.payment.merchant),
                "amount": .number(FinanceToolkitCompute.round2(transaction.amount)),
                "currency": .string(transaction.currency),
                "category": .string(transaction.category),
                "account": transaction.accountId.flatMap { id in store.accounts.first { $0.id == id }?.name }.map(JSONValue.string) ?? .null,
                "guessed": .array(capture.guesses.map(\.rawValue).sorted().map(JSONValue.string)),
            ]
        }
        return [
            "payments": .array(payments),
            "total": .number(Double(queue.payments.count)),
            // A charge that may be a subscription's, a pair that may be a transfer: answered on
            // the To review screen (an open block with the destination "review").
            "questions_on_screen": .number(Double(queue.questions)),
        ]
    }

    /// `draft_review_confirm`: the payments that are right as they were guessed, one draft.
    func draftReviewConfirm(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_review_confirm")) }
        let args = try input.decoded(as: ConfirmInput.self)
        let queue = reviewQueue().payments
        guard !queue.isEmpty else { throw FinanceToolError(message: "Nothing is on review.") }
        let chosen: [Transaction]
        var skipped: [JSONValue] = []
        if args.all == true {
            chosen = queue.prefix(Self.reviewLimit).map(\.transaction)
        } else {
            var seen: Set<String> = []
            let ids = (args.transactionIds ?? []).filter { seen.insert($0).inserted }
            guard !ids.isEmpty else { throw FinanceToolError(message: "Give transaction_ids from get_review_queue, or all true.") }
            guard ids.count <= Self.reviewLimit else {
                throw FinanceToolError(message: "At most \(Self.reviewLimit) payments in one draft.")
            }
            let byId = Dictionary(uniqueKeysWithValues: queue.map { ($0.transaction.id, $0.transaction) })
            chosen = ids.compactMap { byId[$0] }
            skipped = ids.filter { byId[$0] == nil }.map {
                ["transaction_id": .string($0), "reason": "Not on review (already confirmed, or a question for the To review screen)."]
            }
        }
        guard !chosen.isEmpty else { return .failure("None of these payments is on review. Read get_review_queue again.") }
        let id = drafts.add(chosen.map(AgentDraftOperation.reviewConfirm))
        return .success([
            "draft_id": .string(id),
            "count": .number(Double(chosen.count)),
            "left_on_review": .number(Double(queue.count - chosen.count)),
            "skipped": .array(skipped),
            "saved": false,
        ])
    }

    /// What a confirm draft will do (FinanceToolkit.describe).
    func describeReview(_ operation: AgentDraftOperation) -> JSONValue {
        guard case .reviewConfirm(let transaction) = operation else { return .null }
        return [
            "type": "review_confirm",
            "transaction_id": .string(transaction.id),
            "date": .string(transaction.date),
            "merchant": .string(transaction.description),
            "category": .string(transaction.category),
        ]
    }
}
