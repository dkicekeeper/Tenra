//
//  LoansCardView.swift
//  Tenra
//
//  Summary card for Home screen showing total debt,
//  monthly payment, and active loans count.
//

import SwiftUI

struct LoansCardView: View {
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel

    private var loans: [Account] {
        loansViewModel.loans
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    var body: some View {
        FinanceCard(
            title: String(localized: "loan.listTitle", defaultValue: "Loans"),
            isEmpty: loans.isEmpty,
            emptyTitle: String(localized: "loan.emptyTitle", defaultValue: "No Loans"),
            subtitle: String(format: String(localized: "loan.activeCount", defaultValue: "%d active loans"), loans.count)
        ) {
            FormattedAmountText(
                amount: totalDebt,
                currency: baseCurrency,
                fontSize: AppTypography.h2,
                fontWeight: .bold,
                color: AppColors.textPrimary
            )
        } trailing: {
            loanIcons
        }
    }

    // MARK: - Computed

    private var totalDebt: Double {
        loans.compactMap { $0.loanInfo?.remainingPrincipal }
            .reduce(Decimal(0), +)
            .toDouble()
    }

    // MARK: - Icons

    private var loanIcons: some View {
        PackedCircleIconsView(
            items: loans.map { loan in
                PackedCircleItem(
                    id: loan.id,
                    iconSource: loan.iconSource,
                    amount: loan.loanInfo.map { ($0.remainingPrincipal as NSDecimalNumber).doubleValue } ?? 0
                )
            }
        )
    }
}

// MARK: - Decimal Helper

private extension Decimal {
    func toDouble() -> Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - Previews

#Preview("Loans Card") {
    let coordinator = AppCoordinator()
    let sampleLoans: [Account] = [
        Account(
            id: "preview-loan-1",
            name: "Car Loan",
            currency: "KZT",
            iconSource: .brandService("halykbank.kz"),
            loanInfo: LoanInfo(
                bankName: "Halyk Bank",
                loanType: .annuity,
                originalPrincipal: 5_000_000,
                remainingPrincipal: 3_500_000,
                interestRateAnnual: 18.5,
                termMonths: 36,
                startDate: "2025-06-01",
                paymentDay: 15,
                paymentsMade: 9
            ),
            initialBalance: 3_500_000
        ),
        Account(
            id: "preview-loan-2",
            name: "iPhone Installment",
            currency: "KZT",
            iconSource: .brandService("kaspi.kz"),
            loanInfo: LoanInfo(
                bankName: "Kaspi Bank",
                loanType: .installment,
                originalPrincipal: 600_000,
                remainingPrincipal: 400_000,
                interestRateAnnual: 0,
                termMonths: 12,
                startDate: "2026-01-15",
                paymentDay: 15,
                paymentsMade: 2
            ),
            initialBalance: 400_000
        )
    ]
    let _ = sampleLoans.forEach { coordinator.transactionStore.addAccount($0) }

    LoansCardView(
        loansViewModel: coordinator.loansViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .padding()
}

#Preview("Loans Card - Empty") {
    let coordinator = AppCoordinator()

    LoansCardView(
        loansViewModel: coordinator.loansViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .padding()
}
