//
//  ImportTransferHistory.swift
//  Tenra
//
//  Learns "this statement row is a transfer to my other account" from the
//  transfers the user already has, the same way category suggestions learn from
//  history: no separate rule store, so changing a row back teaches it too.
//
//  A saved transfer from Kaspi to Freedom described "Перевод · Асан Б., Freedom
//  Bank" means: on the Kaspi statement, an outgoing row with that description is
//  a transfer to Freedom. Plain spending/income rows with the same description
//  vote against it, so a merchant the user files as spending most of the time is
//  never turned into a transfer.
//
//  Pure and `nonisolated`: built in `Task.detached` over every saved transaction.
//

import Foundation

nonisolated enum ImportTransferHistory {

    enum Direction: String, Sendable {
        /// Money left the statement's account (the row is an expense).
        case outgoing
        /// Money came into the statement's account (the row is income).
        case incoming
    }

    struct Index: Sendable, Equatable {
        /// "\(accountId)|\(direction)|\(normalizedMerchant)" → counterpart account id
        /// (`plainVote` for a plain expense/income row) → count
        var counts: [String: [String: Int]] = [:]
    }

    private static let plainVote = ""

    static func build(from transactions: [Transaction]) -> Index {
        var index = Index()
        func vote(_ accountId: String?, _ direction: Direction, _ description: String, for counterpart: String) {
            guard let accountId, !accountId.isEmpty else { return }
            let merchant = CategorySuggestionService.normalizedMerchant(description)
            guard merchant.count >= CategorySuggestionService.minimumMerchantLength else { return }
            index.counts[key(accountId, direction, merchant), default: [:]][counterpart, default: 0] += 1
        }
        for tx in transactions {
            switch tx.type {
            case .internalTransfer:
                guard let source = tx.accountId, let target = tx.targetAccountId,
                      !source.isEmpty, !target.isEmpty, source != target else { continue }
                vote(source, .outgoing, tx.description, for: target)
                vote(target, .incoming, tx.description, for: source)
            case .expense:
                vote(tx.accountId, .outgoing, tx.description, for: plainVote)
            case .income:
                vote(tx.accountId, .incoming, tx.description, for: plainVote)
            default:
                continue
            }
        }
        return index
    }

    /// The account a row with this description usually moves money to or from, when
    /// transfers to that account outnumber plain spending/income with the same
    /// description. nil otherwise.
    static func counterpart(
        accountId: String,
        direction: Direction,
        description: String,
        in index: Index
    ) -> String? {
        let merchant = CategorySuggestionService.normalizedMerchant(description)
        guard merchant.count >= CategorySuggestionService.minimumMerchantLength,
              let votes = index.counts[key(accountId, direction, merchant)] else { return nil }
        let plain = votes[plainVote] ?? 0
        let best = votes
            .filter { $0.key != plainVote }
            .max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }
        guard let best, best.value > plain else { return nil }
        return best.key
    }

    private static func key(_ accountId: String, _ direction: Direction, _ merchant: String) -> String {
        "\(accountId)|\(direction.rawValue)|\(merchant)"
    }
}
