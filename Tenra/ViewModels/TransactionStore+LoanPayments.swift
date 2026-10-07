//
//  TransactionStore+LoanPayments.swift
//  Tenra
//
//  A deleted loan payment comes off its loan. A loan keeps its state in `LoanInfo`
//  (remaining principal, interest paid, payments made, last payment date, early
//  repayments), written when a payment is recorded. Nothing undid it on delete: the debt
//  stayed reduced (the loan's balance IS its remaining principal) and the month kept
//  showing "Paid". This runs inside `apply(.deleted)`, so every path that deletes a
//  transaction rolls its loan back: a single delete, an account's transactions, a
//  series' transactions.
//

import Foundation

extension TransactionStore {

    /// Takes `payment`'s own effect off its loan (`LoanPaymentService.reversingPayment`)
    /// and moves the loan's balance with it. A no-op for anything but a `.loanPayment` /
    /// `.loanEarlyRepayment` to a loan that still exists (orientation contract:
    /// `targetAccountId` = loan).
    ///
    /// Called after the transaction left the indexes, so the loan's bucket holds only the
    /// payments that remain.
    func rollBackLoanPayment(_ payment: Transaction) async {
        guard payment.type == .loanPayment || payment.type == .loanEarlyRepayment,
              let loanId = payment.targetAccountId,
              let index = accounts.firstIndex(where: { $0.id == loanId }),
              let info = accounts[index].loanInfo else { return }

        var loan = accounts[index]
        let loanCurrency = loan.currency
        let rates = RateSnapshot()
        let remainingPayments = (transactionsByAccount[loanId] ?? [])
            .filter { ($0.type == .loanPayment || $0.type == .loanEarlyRepayment) && $0.targetAccountId == loanId }
            .map { recordedPayment($0, loanCurrency: loanCurrency, rates: rates) }
        let rolledBack = LoanPaymentService.reversingPayment(
            recordedPayment(payment, loanCurrency: loanCurrency, rates: rates),
            in: info,
            otherPayments: remainingPayments
        )
        guard rolledBack != info else { return }

        loan.loanInfo = rolledBack
        accounts[index] = loan
        rebuildAccountById()

        // The loan's balance is its remaining principal (BalanceCoordinator.loanDebt), as
        // AccountsViewModel.updateLoan keeps it after a payment.
        let debt = NSDecimalNumber(decimal: rolledBack.remainingPrincipal).doubleValue
        await balanceCoordinator.updateForAccount(loan, newBalance: debt)
        await balanceCoordinator.setInitialBalance(debt, for: loanId)

        scheduleLoanRollbackPersist()
    }

    /// `transaction` in its loan's currency, the paying account's currency read here.
    private func recordedPayment(
        _ transaction: Transaction,
        loanCurrency: String,
        rates: RateSnapshot
    ) -> LoanPaymentService.RecordedPayment {
        LoanPaymentService.recordedPayment(
            transaction,
            loanCurrency: loanCurrency,
            sourceCurrency: transaction.accountId.flatMap { accountById[$0]?.currency },
            rates: rates
        )
    }

    /// Saves the accounts once a burst of rollbacks is over. Deleting an account with its
    /// transactions (or a loan with its payments) deletes the account right after: a
    /// whole-table save per deleted row could still be running then and make the
    /// coordinator drop the account delete's own save (`savingInProgress`), bringing the
    /// account back on the next launch. The deferred save takes the accounts as they are when
    /// it runs, so it never brings back what was deleted meanwhile.
    private func scheduleLoanRollbackPersist() {
        guard !isImporting else { return }
        loanRollbackPersistTask?.cancel()
        loanRollbackPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.persistAccountsToRepository()
        }
    }
}
