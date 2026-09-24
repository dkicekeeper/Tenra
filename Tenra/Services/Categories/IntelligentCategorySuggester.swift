//
//  IntelligentCategorySuggester.swift
//  Tenra
//
//  The last category tier: Apple Intelligence (the on-device model, nothing leaves
//  the phone) for rows that history, the brand list and the keyword dictionary
//  could not place. It runs AFTER the review screen is shown and fills rows as
//  answers arrive, so a slow model never delays the import.
//
//  The model can only answer with one of the user's own category names or NONE:
//  the answer schema is an `anyOf` over those names, built at run time
//  (`DynamicGenerationSchema`). It cannot invent a category, and a row it cannot
//  place stays uncategorized. Same merchant, same answer: rows are deduplicated by
//  `normalizedMerchant` before any request, and a request carries at most
//  `batchSize` merchants to stay far inside the context window.
//
//  Once saved, an accepted answer is history, so the next import suggests it from
//  the history tier without asking the model again.
//
//  Console.app, subsystem `Tenra`, category `CategoryIntelligence`: batch sizes,
//  timings and failures, for checking behavior on a real device.
//

import Foundation
import FoundationModels
import os

nonisolated enum IntelligentCategorySuggester {

    struct Item: Sendable, Equatable {
        let id: String
        let description: String
        let type: TransactionType
    }

    /// One request: distinct merchants of one type and that type's categories.
    struct Batch: Sendable, Equatable {
        let type: TransactionType
        /// Raw descriptions, one per distinct normalized merchant.
        let merchants: [String]
        let categories: [String]
    }

    static let batchSize = 15
    /// The answer for "none of these"; never a real category name the user could have.
    static let noneChoice = "NONE"

    private static let logger = Logger(subsystem: "Tenra", category: "CategoryIntelligence")

    private static let instructions = """
    You sort bank statement rows and receipts into the user's own categories. For each \
    numbered row you pick exactly one category from the allowed list, or NONE when the \
    row does not clearly belong to one of them. Rows are merchant names or payment \
    descriptions as the bank printed them, often in capital letters with a city and a \
    country code. A transfer to a person, a cash withdrawal, or a payment whose purpose \
    you cannot tell is NONE. Never pick a category because of a single ambiguous word.
    """

    // MARK: - Planning (pure)

    /// Distinct merchants per type, first description of each kept, in row order,
    /// split into requests. Types without categories and merchants too short to
    /// carry meaning are left out.
    static func batches(for items: [Item], categories: [TransactionType: [String]]) -> [Batch] {
        var order: [TransactionType] = []
        var merchantsByType: [TransactionType: [String]] = [:]
        var seen = Set<String>()
        for item in items {
            guard let names = categories[item.type], !names.isEmpty else { continue }
            let key = CategorySuggestionService.normalizedMerchant(item.description)
            guard key.count >= CategorySuggestionService.minimumMerchantLength,
                  seen.insert("\(item.type.rawValue)|\(key)").inserted else { continue }
            if merchantsByType[item.type] == nil { order.append(item.type) }
            merchantsByType[item.type, default: []].append(item.description)
        }
        return order.flatMap { type -> [Batch] in
            let merchants = merchantsByType[type] ?? []
            return stride(from: 0, to: merchants.count, by: batchSize).map { start in
                Batch(type: type,
                      merchants: Array(merchants[start..<min(start + batchSize, merchants.count)]),
                      categories: categories[type] ?? [])
            }
        }
    }

    /// Row id → category for every row whose merchant got a real answer.
    /// `answers` maps a raw merchant description to the model's choice.
    static func assign(_ answers: [String: String], type: TransactionType, categories: [String], to items: [Item]) -> [String: String] {
        var byMerchant: [String: String] = [:]
        for (description, choice) in answers where choice != noneChoice && categories.contains(choice) {
            byMerchant[CategorySuggestionService.normalizedMerchant(description)] = choice
        }
        var result: [String: String] = [:]
        for item in items where item.type == type {
            if let choice = byMerchant[CategorySuggestionService.normalizedMerchant(item.description)] {
                result[item.id] = choice
            }
        }
        return result
    }

    static func prompt(for batch: Batch) -> String {
        let kind = batch.type == .income ? "income" : "spending"
        let rows = batch.merchants.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return """
        Allowed \(kind) categories: \(batch.categories.joined(separator: ", "))

        Rows:
        \(rows)

        For each row, answer the category it belongs to, or NONE.
        """
    }

    // MARK: - Model

    /// Asks the model batch by batch and reports each batch's row id → category as it
    /// arrives. Does nothing when Apple Intelligence is unavailable. Throws only
    /// `CancellationError`; any other failure ends the run quietly (the rows simply
    /// stay without a suggestion).
    static func suggest(
        items: [Item],
        categories: [TransactionType: [String]],
        onBatch: @MainActor @Sendable ([String: String]) -> Void
    ) async throws {
        try Task.checkCancellation()
        guard IntelligenceAvailability.isAvailable else {
            logger.info("skipped: \(String(describing: IntelligenceAvailability.status), privacy: .public)")
            return
        }
        let batches = batches(for: items, categories: categories)
        guard !batches.isEmpty else { return }
        logger.info("\(batches.count, privacy: .public) batches for \(items.count, privacy: .public) rows")

        var failures = 0
        for batch in batches {
            try Task.checkCancellation()
            let started = Date()
            do {
                let answers = try await answers(for: batch)
                let assigned = assign(answers, type: batch.type, categories: batch.categories, to: items)
                logger.info("batch of \(batch.merchants.count, privacy: .public): \(assigned.count, privacy: .public) rows placed in \(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)s")
                await onBatch(assigned)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                failures += 1
                logger.error("batch failed: \(String(describing: error), privacy: .public)")
                // An unsupported language or a missing model fails every batch alike.
                if failures >= 2 { return }
            }
        }
    }

    /// Raw merchant description → the model's choice, for one batch.
    private static func answers(for batch: Batch) async throws -> [String: String] {
        let choice = DynamicGenerationSchema(
            name: "Category",
            description: "One of the allowed categories, or \(noneChoice).",
            anyOf: batch.categories + [noneChoice]
        )
        let properties = batch.merchants.enumerated().map { index, merchant in
            DynamicGenerationSchema.Property(
                name: "row\(index + 1)",
                description: merchant,
                schema: DynamicGenerationSchema(referenceTo: "Category")
            )
        }
        let root = DynamicGenerationSchema(name: "Categorization", properties: properties)
        let schema = try GenerationSchema(root: root, dependencies: [choice])

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: prompt(for: batch),
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy)
        )
        var result: [String: String] = [:]
        for (index, merchant) in batch.merchants.enumerated() {
            if let answer = try? response.content.value(String.self, forProperty: "row\(index + 1)") {
                result[merchant] = answer
            }
        }
        return result
    }
}
