// The public calculators' math against closed-form values (docs/public/assets/calc.js).
//   node scripts/test_site_calc.js
const assert = require("assert");
const { deposit, loan } = require("../docs/public/assets/calc.js");
const near = (actual, expected, tolerance = 0.01) =>
    assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} is not ${expected}`);

// Deposits: 1 000 000 at 15% for a year.
near(deposit(1e6, 15, 12, 0, true).interest, 160754.52);
near(deposit(1e6, 15, 12, 0, true).effectiveRate, 16.0755, 0.0001);
near(deposit(1e6, 15, 12, 0, false).interest, 150000);
near(deposit(1e6, 15, 12, 0, false).effectiveRate, 15);
// 50 000 after each month but the last: 11 top-ups.
const toppedUp = deposit(1e6, 15, 12, 50000, true);
near(toppedUp.total, 1753772.59);
near(toppedUp.contributed, 1550000);
near(deposit(1e6, 0, 12, 0, true).interest, 0);

// Loans: 1 000 000 at 20% for two years.
const annuity = loan(1e6, 20, 24, "annuity", 0);
near(annuity.payment, 50895.80);
near(annuity.interest, 221499.26);
assert.strictEqual(annuity.months, 24);
near(annuity.rows[23].balance, 0);
near(loan(1e4, 9, 24, "annuity", 0).payment, 456.85);

const diff = loan(1e6, 20, 24, "diff", 0);
near(diff.payment, 58333.33);
near(diff.lastPayment, 42361.11);
near(diff.interest, 208333.33);
assert.strictEqual(diff.months, 24);

// An instalment plan: no interest, equal parts.
const plan = loan(120000, 0, 12, "annuity", 0);
near(plan.payment, 10000);
near(plan.interest, 0);
assert.strictEqual(plan.months, 12);

// Extra payments shorten the term and the interest, and never overpay the principal.
const early = loan(1e6, 20, 24, "annuity", 20000);
assert.ok(early.months < 24 && early.interest < annuity.interest);
near(early.rows.reduce((sum, row) => sum + row.principal, 0), 1e6);
near(early.payment, 50895.80);

console.log("calc.js: all checks passed");
