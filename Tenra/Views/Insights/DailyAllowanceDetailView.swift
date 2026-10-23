//
//  DailyAllowanceDetailView.swift
//  Tenra
//
//  "For today", opened from Analytics (DailyAllowanceLink): the figure, then how it is reached
//  (the everyday accounts' balance now, less the payments set aside, leaves what is free,
//  spread over the days to the next income) and each payment set aside. "Ask Ten" in the bar
//  where the assistant runs: it answers from the same forecast.
//

import SwiftUI

struct DailyAllowanceDetailView: View {
    let value: DailyAllowance.Value

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                HeroSection(
                    icon: .sfSymbol("sun.max.fill"),
                    title: String(localized: "home.today.title"),
                    iconTint: .monochrome(AppColors.accent),
                    primaryAmount: value.amount,
                    primaryCurrency: value.currency,
                    subtitle: span
                )
                .screenPadding()
                .scrollHero()

                FormSection(
                    header: String(localized: "allowance.detail.how"),
                    footer: String(localized: "allowance.detail.footer")
                ) {
                    AmountRow(
                        String(localized: "allowance.detail.balance"),
                        leading: .tinted(.sfSymbol("creditcard.fill"), AppColors.accent),
                        value: .amount(value.startBalance),
                        currency: value.currency
                    )
                    AmountRow(
                        String(localized: "allowance.detail.setAside"),
                        leading: .tinted(.sfSymbol("calendar.badge.clock"), AppColors.warning),
                        value: .amount(-value.setAsideExact),
                        currency: value.currency
                    )
                    AmountRow(
                        String(localized: "allowance.detail.free"),
                        leading: .tinted(.sfSymbol("checkmark.circle.fill"), AppColors.success),
                        value: .amount(value.free, color: value.free < 0 ? AppColors.destructive : AppColors.textPrimary),
                        currency: value.currency
                    )
                    UniversalRow(
                        String(localized: "allowance.detail.days"),
                        icon: "calendar",
                        value: "\(value.days)"
                    )
                }
                .screenPadding()

                if !value.outflows.isEmpty {
                    FormSection(header: String(localized: "allowance.detail.payments")) {
                        ForEach(Array(value.outflows.enumerated()), id: \.offset) { _, outflow in
                            AmountRow(
                                outflow.label,
                                subtitle: DateFormatters.displayDateOmittingCurrentYear(outflow.date),
                                subtitleLineLimit: 1,
                                leading: .tinted(.sfSymbol("arrow.up.right"), AppColors.warning),
                                value: .amount(outflow.amount),
                                currency: value.currency
                            )
                        }
                    }
                    .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "home.today.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskAssistantToolbarButton(topic: .allowance)
            }
        }
    }

    /// "A day until your income on 28 Oct" / "A day until the end of the month".
    private var span: String {
        guard let income = value.income else { return String(localized: "home.today.untilMonthEnd") }
        return String(
            format: String(localized: "home.today.untilIncome"),
            income.formatted(.dateTime.day().month(.abbreviated))
        )
    }
}

private extension DailyAllowance.Value {
    /// The payments set aside, exact (`setAside` is rounded up for the card), so the rows add up.
    var setAsideExact: Double { outflows.reduce(0) { $0 + $1.amount } }
}

#Preview {
    let today = Date()
    NavigationStack {
        DailyAllowanceDetailView(value: DailyAllowance.Value(
            amount: 8_400,
            currency: "KZT",
            income: today.addingTimeInterval(6 * 86_400),
            setAside: 23_990,
            startBalance: 74_390,
            free: 50_400,
            days: 6,
            outflows: [
                DailyAllowance.Outflow(date: today.addingTimeInterval(86_400), label: "Netflix", amount: 4_990),
                DailyAllowance.Outflow(date: today.addingTimeInterval(3 * 86_400), label: "Mobile", amount: 19_000)
            ]
        ))
    }
    .environment(AppCoordinator())
}
