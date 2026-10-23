//
//  DailyAllowanceLink.swift
//  Tenra
//
//  "For today" on Analytics, under the period's stat cards: how much can go out a day until the
//  next income (DailyAllowance, Ten's forecast_balance), as an insight like the others. The
//  feed's card (InsightsCardView) opens the insight screen (InsightDetailView, through
//  InsightsView's destination for an Insight): the hero, "How it's calculated" and each payment
//  set aside with its logo or category icon. Self-contained: reads the coordinator and
//  recomputes whenever an input changes. Hidden without an account that counts for today.
//

import SwiftUI

struct DailyAllowanceLink: View {
    @Environment(AppCoordinator.self) private var coordinator

    /// InsightsView's namespace: the card is the zoom source of its screen, like the feed's.
    let namespace: Namespace.ID

    @State private var value: DailyAllowance.Value?

    private var store: TransactionStore { coordinator.transactionStore }

    // Everything "For today" depends on (CLAUDE.md, red flag 12): the history, the accounts,
    // the subscriptions and other series before the next income, the income categories that
    // find that income, the rates, the base currency and the day.
    private struct Trigger: Equatable {
        let txVersion: Int
        let accountsVersion: Int
        let series: [RecurringSeries]
        let categoriesVersion: Int
        let ratesVersion: Int
        let baseCurrency: String
        let day: Date
        let isFullyInitialized: Bool
    }

    private var trigger: Trigger {
        // Both versions are @ObservationIgnored: touch the observable arrays so `body` re-runs.
        _ = store.transactions.count
        _ = store.accounts.count
        return Trigger(
            txVersion: store.mutationVersion,
            accountsVersion: store.accountsMutationVersion,
            series: store.recurringSeries,
            categoriesVersion: store.categoriesMutationVersion,
            ratesVersion: store.currencyRatesVersion,
            baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
            day: Calendar.current.startOfDay(for: Date()),
            isFullyInitialized: coordinator.isFullyInitialized
        )
    }

    var body: some View {
        // A ZStack, not a Group: a Group without content hands `.task` to no view, and the
        // first value would never be computed. Empty, it takes no height.
        ZStack {
            if let value {
                let allowance = makeInsight(for: value)
                NavigationLink(value: allowance) {
                    InsightsCardView(insight: allowance)
                        .matchedTransitionSource(id: allowance.id, in: namespace)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights.allowance")
                .transition(.opacity)
            }
        }
        .task(id: trigger) {
            guard coordinator.isFullyInitialized, !store.isImporting else { return }
            let computed = await DailyAllowance.value(store: store)
            guard !Task.isCancelled else { return }
            withAnimation(AppAnimation.smooth) { value = computed }
        }
    }

    // MARK: - The insight

    private func makeInsight(for value: DailyAllowance.Value) -> Insight {
        let span = Self.span(until: value.income)
        var subtitle = span
        if value.setAside > 0 {
            // The amount never breaks across lines: its group separators become non-breaking.
            let amount = Formatting.formatCurrencySmart(value.setAside, currency: value.currency)
                .replacingOccurrences(of: " ", with: "\u{00A0}")
            subtitle += "\n" + String(format: String(localized: "home.today.setAside"), amount)
        }
        return Insight(
            id: "daily_allowance",
            type: .dailyAllowance,
            title: String(localized: "home.today.title"),
            subtitle: subtitle,
            metric: InsightMetric(
                value: value.amount,
                formattedValue: Formatting.formatCurrencySmart(value.amount, currency: value.currency),
                currency: value.currency,
                unit: nil
            ),
            trend: nil,
            severity: value.amount > 0 ? .neutral : .warning,
            category: .forecasting,
            detailData: .dailyAllowance(DailyAllowanceDetail(
                formula: formula(for: value),
                payments: value.outflows.enumerated().map { index, outflow in payment(outflow, index: index) },
                missingRates: value.missingRates
            )),
            // While amounts are hidden, the subtitle keeps only the span.
            hiddenSubtitle: span
        )
    }

    /// "A day until your income on 28 Oct" / "A day until the end of the month".
    private static func span(until income: Date?) -> String {
        guard let income else { return String(localized: "home.today.untilMonthEnd") }
        return String(
            format: String(localized: "home.today.untilIncome"),
            income.formatted(.dateTime.day().month(.abbreviated))
        )
    }

    /// How it is reached, exact (the card's figures are rounded), so the rows add up.
    private func formula(for value: DailyAllowance.Value) -> InsightFormulaModel {
        let setAside = value.outflows.reduce(0) { $0 + $1.amount }
        return InsightFormulaModel(
            id: "dailyAllowance",
            titleKey: "home.today.title",
            icon: "sun.max.fill",
            color: AppColors.accent,
            heroValueText: Formatting.formatCurrencySmart(value.amount, currency: value.currency),
            heroLabelKey: "home.today.title",
            formulaHeaderKey: "allowance.detail.how",
            formulaRows: [
                InsightFormulaRow(id: "balance", labelKey: "allowance.detail.balance", value: value.startBalance, kind: .currency),
                InsightFormulaRow(id: "setAside", labelKey: "allowance.detail.setAside", value: -setAside, kind: .currency),
                InsightFormulaRow(id: "free", labelKey: "allowance.detail.free", value: value.free, kind: .currency, isEmphasised: true),
                InsightFormulaRow(id: "days", labelKey: "allowance.detail.days", value: Double(value.days), kind: .rawText("\(value.days)")),
            ],
            explainerKey: "allowance.detail.footer",
            recommendation: "",
            baseCurrency: value.currency
        )
    }

    /// A payment with its icon, as History draws it: the subscription's or the loan bank's logo,
    /// else the category's symbol on its colour.
    private func payment(_ outflow: DailyAllowance.Outflow, index: Int) -> AllowancePaymentItem {
        var logo: IconSource?
        var category = outflow.category
        if let id = outflow.seriesId, let series = store.recurringSeries.first(where: { $0.id == id }) {
            logo = series.iconSource
            category = category ?? series.category
        } else if let id = outflow.loanAccountId {
            logo = store.accounts.first(where: { $0.id == id })?.iconSource
            category = category ?? TransactionType.loanPaymentCategoryName
        }
        let id = "\(index)-\(outflow.label)"
        if let logo, case .brandService = logo {
            return AllowancePaymentItem(id: id, label: outflow.label, date: outflow.date, amount: outflow.amount, icon: logo, tint: nil)
        }
        let style = CategoryStyleHelper.cached(
            category: category ?? "",
            type: outflow.loanAccountId != nil ? .loanPayment : .expense,
            customCategories: store.categories
        )
        return AllowancePaymentItem(
            id: id,
            label: outflow.label,
            date: outflow.date,
            amount: outflow.amount,
            icon: logo ?? .sfSymbol(style.iconName),
            tint: style.primaryColor
        )
    }
}
