// The planning formulas of simulate_loan and project_savings, as the phone computes them
// (Tenra/Services/Loans/LoanWhatIf.swift, Tenra/Services/Agent/SavingsProjection.swift).
// Keep the two in step: test/eval.test.ts and AgentPlanningTests pin the same figures.

export interface LoanPlan {
  principal: number;
  ratePercent: number;
  monthlyPayment: number;
  monthsLeft: number;
  totalInterest: number;
}

export interface LoanScenario {
  newRatePercent?: number;
  newMonths?: number;
  fees: number;
  extraMonthly: number;
  oneOff: number;
  oneOffReducesPayment: boolean;
}

export class PlanningError extends Error {}

/** Months until repaid with this payment and the interest paid; null when it never is. */
export function repay(principal: number, ratePercent: number, payment: number): { months: number; interest: number } | null {
  if (principal <= 0.005) return { months: 0, interest: 0 };
  if (payment <= 0) return null;
  const rate = ratePercent / 100 / 12;
  let left = principal;
  let interest = 0;
  let months = 0;
  while (left > 0.005 && months < 1200) {
    const monthInterest = left * rate;
    if (payment <= monthInterest) return null;
    interest += monthInterest;
    left -= Math.min(payment, left + monthInterest) - monthInterest;
    months += 1;
  }
  return { months, interest };
}

export function annuity(principal: number, ratePercent: number, months: number): number {
  if (months <= 0) return principal;
  const rate = ratePercent / 100 / 12;
  if (rate <= 0) return principal / months;
  const power = (1 + rate) ** months;
  return (principal * rate * power) / (power - 1);
}

export function loanPlan(principal: number, ratePercent: number, payment: number | null, monthsLeft: number | null): LoanPlan {
  const monthly = payment && payment > 0 ? payment : annuity(principal, ratePercent, monthsLeft ?? 0);
  const run = repay(principal, ratePercent, monthly);
  if (!run) throw new PlanningError("The loan's payment does not cover its monthly interest.");
  return { principal, ratePercent, monthlyPayment: monthly, monthsLeft: run.months, totalInterest: run.interest };
}

export function applyScenario(scenario: LoanScenario, current: LoanPlan): LoanPlan {
  const principal = current.principal - scenario.oneOff;
  if (principal <= 0.005) throw new PlanningError("one_off covers the whole loan: nothing would be left to compare.");
  const rate = scenario.newRatePercent ?? current.ratePercent;
  const refinances = scenario.newRatePercent !== undefined || scenario.newMonths !== undefined;
  const base =
    refinances || (scenario.oneOff > 0 && scenario.oneOffReducesPayment)
      ? annuity(principal, rate, scenario.newMonths ?? current.monthsLeft)
      : current.monthlyPayment;
  const payment = base + scenario.extraMonthly;
  const run = repay(principal, rate, payment);
  if (!run) throw new PlanningError("In this scenario the payment does not cover the monthly interest.");
  return { principal, ratePercent: rate, monthlyPayment: payment, monthsLeft: run.months, totalInterest: run.interest };
}

export function breakEvenMonths(fees: number, current: LoanPlan, scenario: LoanPlan): number | null {
  const saving = current.monthlyPayment - scenario.monthlyPayment;
  if (fees <= 0 || saving <= 0.005) return null;
  return Math.ceil(fees / saving);
}

export interface SavingsYear {
  year: number;
  total: number;
  contributed: number;
}

/** Monthly compounding at the rate that gives the annual return over a year; contributions at
 *  the end of each month. */
export function projectSavings(start: number, monthly: number, annualReturnPercent: number, years: number, inflationPercent: number | null) {
  const rate = (1 + annualReturnPercent / 100) ** (1 / 12) - 1;
  let balance = start;
  let contributed = start;
  const rows: SavingsYear[] = [];
  for (let month = 1; month <= years * 12; month++) {
    balance = balance * (1 + rate) + monthly;
    contributed += monthly;
    if (month % 12 === 0) rows.push({ year: month / 12, total: balance, contributed });
  }
  const real = inflationPercent === null ? null : balance / (1 + inflationPercent / 100) ** years;
  return { finalAmount: balance, contributed, finalAmountReal: real, years: rows };
}
