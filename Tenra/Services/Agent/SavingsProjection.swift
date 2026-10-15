//
//  SavingsProjection.swift
//  Tenra
//
//  Compound growth of regular saving or investing for the assistant's `project_savings`
//  (docs/plan-ai-assistant.md §3.1): a starting amount, a contribution at the end of every
//  month and an assumed annual return, compounded monthly at the rate that gives that return
//  over a year. The return is the person's or the model's assumption, never a forecast. The
//  same formula runs in server/assistant/eval/simulator.ts, keep them in step.
//

import Foundation

nonisolated enum SavingsProjection {
    struct Year: Equatable {
        /// 1-based year from now.
        let year: Int
        let total: Double
        let contributed: Double
    }

    struct Result: Equatable {
        let finalAmount: Double
        let contributed: Double
        /// The final amount in today's money, when an inflation rate is given.
        let finalAmountReal: Double?
        let years: [Year]

        var growth: Double { finalAmount - contributed }
    }

    static func project(start: Double, monthly: Double, annualReturnPercent: Double, years: Int, inflationPercent: Double?) -> Result {
        let rate = pow(1 + annualReturnPercent / 100, 1.0 / 12) - 1
        var balance = start, contributed = start
        var rows: [Year] = []
        for month in stride(from: 1, through: years * 12, by: 1) {
            balance = balance * (1 + rate) + monthly
            contributed += monthly
            if month % 12 == 0 {
                rows.append(Year(year: month / 12, total: balance, contributed: contributed))
            }
        }
        let real = inflationPercent.map { balance / pow(1 + $0 / 100, Double(years)) }
        return Result(finalAmount: balance, contributed: contributed, finalAmountReal: real, years: rows)
    }
}
