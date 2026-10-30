// Executes the assistant's tools over the synthetic fixture, the way FinanceToolkit does on
// the phone. Simplified (fixed FX rate, monthly budgets only) but deterministic, so the
// grader can compare the model's references with known values.

import {
  ACCOUNTS,
  ASSETS,
  BASE_CURRENCY,
  BUDGETS,
  CATEGORIES,
  DEBTS,
  FACTS,
  GOALS,
  LOAN_TERMS,
  RECURRING,
  TODAY,
  TRANSACTIONS,
  USD_RATE,
  type Transaction,
} from "./fixture";
import { applyScenario, breakEvenMonths, loanPlan, PlanningError, projectSavings as growSavings, type LoanPlan, type LoanScenario } from "./planning";

type Input = Record<string, unknown>;
export class ToolInputError extends Error {}

const toBase = (amount: number, currency: string) => (currency === "USD" ? amount * USD_RATE : amount);
const round = (n: number) => Math.round(n * 100) / 100;
const categoryName = (id: string) => CATEGORIES.find((c) => c.id === id)?.name ?? id;
const accountName = (id: string) => ACCOUNTS.find((a) => a.id === id)?.name ?? id;

function str(input: Input, key: string, required = false): string | undefined {
  const value = input[key];
  if (value === undefined || value === null) {
    if (required) throw new ToolInputError(`${key} is required`);
    return undefined;
  }
  if (typeof value !== "string") throw new ToolInputError(`${key} must be a string`);
  return value;
}

function dateArg(input: Input, key: string, required = false): string | undefined {
  const value = str(input, key, required);
  if (value !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new ToolInputError(`${key} must be YYYY-MM-DD`);
  return value;
}

const list = (input: Input, key: string) => (Array.isArray(input[key]) ? (input[key] as string[]) : undefined);

function filterTx(input: Input, type: string): Transaction[] {
  const from = dateArg(input, "from") ?? "0000-01-01";
  const to = dateArg(input, "to") ?? TODAY;
  const categories = list(input, "category_ids");
  const accounts = list(input, "account_ids");
  return TRANSACTIONS.filter(
    (t) =>
      (type === "any" || t.type === type) &&
      t.date >= from &&
      t.date <= to &&
      t.date <= TODAY &&
      (!categories?.length || categories.includes(t.categoryId)) &&
      (!accounts?.length || accounts.includes(t.accountId)),
  );
}

function weekStart(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  const shift = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - shift);
  return d.toISOString().slice(0, 10);
}

function group(txs: Transaction[], by: string) {
  const key = (t: Transaction) =>
    by === "category" ? t.categoryId : by === "merchant" ? t.merchant : by === "week" ? weekStart(t.date) : by === "month" ? t.date.slice(0, 7) : "all";
  const label = (k: string) => (by === "category" ? categoryName(k) : k);
  const map = new Map<string, { total: number; count: number }>();
  for (const t of txs) {
    const entry = map.get(key(t)) ?? { total: 0, count: 0 };
    entry.total += toBase(t.amount, t.currency);
    entry.count += 1;
    map.set(key(t), entry);
  }
  const total = txs.reduce((n, t) => n + toBase(t.amount, t.currency), 0);
  const groups = [...map.entries()].map(([k, v]) => ({ key: k, label: label(k), total: round(v.total), count: v.count, share: total ? round(v.total / total) : 0 }));
  groups.sort((a, b) => (by === "week" || by === "month" ? a.key.localeCompare(b.key) : b.total - a.total));
  return { total: round(total), groups };
}

function spendingSummary(input: Input) {
  const type = str(input, "type", true)!;
  const by = str(input, "group_by") ?? "none";
  const txs = filterTx(input, type);
  const { total, groups } = group(txs, by);
  return { currency: BASE_CURRENCY, type, from: dateArg(input, "from"), to: dateArg(input, "to") ?? TODAY, total, count: txs.length, groups: by === "none" ? [] : groups };
}

function comparePeriods(input: Input) {
  const type = str(input, "type", true)!;
  const by = str(input, "group_by") ?? "none";
  const current = input.current as Input | undefined;
  const previous = input.previous as Input | undefined;
  if (!current || !previous) throw new ToolInputError("current and previous are required");
  const a = group(filterTx(current, type), by);
  const b = group(filterTx(previous, type), by);
  const keys = new Set([...a.groups, ...b.groups].map((g) => g.key));
  const groups = [...keys]
    .map((k) => {
      const cur = a.groups.find((g) => g.key === k)?.total ?? 0;
      const prev = b.groups.find((g) => g.key === k)?.total ?? 0;
      return { key: k, label: by === "category" ? categoryName(k) : k, current: cur, previous: prev, change: round(cur - prev) };
    })
    .sort((x, y) => Math.abs(y.change) - Math.abs(x.change));
  return {
    currency: BASE_CURRENCY,
    type,
    current: { from: current.from, to: current.to, total: a.total },
    previous: { from: previous.from, to: previous.to, total: b.total },
    change: round(a.total - b.total),
    change_percent: b.total ? round(((a.total - b.total) / b.total) * 100) : null,
    groups: by === "none" ? [] : groups,
  };
}

function searchTransactions(input: Input) {
  const type = str(input, "type") ?? "any";
  const query = str(input, "query")?.toLowerCase();
  const min = typeof input.min_amount === "number" ? input.min_amount : -Infinity;
  const max = typeof input.max_amount === "number" ? input.max_amount : Infinity;
  const limit = Math.min(Math.max(Number(input.limit ?? 20), 1), 50);
  let txs = filterTx(input, type).filter((t) => {
    const base = toBase(t.amount, t.currency);
    return base >= min && base <= max && (!query || t.merchant.toLowerCase().includes(query) || t.note.toLowerCase().includes(query));
  });
  txs = str(input, "sort") === "largest"
    ? [...txs].sort((a, b) => toBase(b.amount, b.currency) - toBase(a.amount, a.currency))
    : [...txs].sort((a, b) => b.date.localeCompare(a.date) || b.id.localeCompare(a.id));
  return {
    currency: BASE_CURRENCY,
    count_total: txs.length,
    items: txs.slice(0, limit).map((t) => ({
      id: t.id, date: t.date, type: t.type, amount: t.amount, currency: t.currency, amount_base: toBase(t.amount, t.currency),
      category_id: t.categoryId, category: categoryName(t.categoryId), merchant: t.merchant, note: t.note,
      account_id: t.accountId, account: accountName(t.accountId),
    })),
  };
}

export function balanceOf(accountId: string): number {
  const account = ACCOUNTS.find((a) => a.id === accountId)!;
  if (account.kind === "loan") {
    const paid = TRANSACTIONS.filter((t) => t.categoryId === "cat_loan").length * 60_000; // principal part
    return account.initial + paid;
  }
  return TRANSACTIONS.reduce((n, t) => {
    if (t.toAccountId === accountId) return n + t.amount;
    if (t.accountId !== accountId) return n;
    return n + (t.type === "income" ? t.amount : -t.amount);
  }, account.initial);
}

function getAccounts() {
  const accounts = ACCOUNTS.map((a) => ({ id: a.id, name: a.name, kind: a.kind, currency: a.currency, balance: round(balanceOf(a.id)), balance_base: round(toBase(balanceOf(a.id), a.currency)) }));
  const assets = accounts.filter((a) => a.kind !== "loan").reduce((n, a) => n + a.balance_base, 0);
  const debts = accounts.filter((a) => a.kind === "loan").reduce((n, a) => n + a.balance_base, 0);
  return { currency: BASE_CURRENCY, total_base: round(assets), net_worth: round(assets + debts), accounts };
}

function daysBetween(a: string, b: string) {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000);
}

function getBudgets(input: Input) {
  const on = dateArg(input, "on_date") ?? TODAY;
  const from = `${on.slice(0, 7)}-01`;
  const end = new Date(Date.UTC(Number(on.slice(0, 4)), Number(on.slice(5, 7)), 0)).toISOString().slice(0, 10);
  return {
    currency: BASE_CURRENCY,
    on_date: on,
    budgets: BUDGETS.map((b) => {
      const spent = filterTx({ from, to: on, category_ids: [b.categoryId] }, "expense").reduce((n, t) => n + toBase(t.amount, t.currency), 0);
      return { category_id: b.categoryId, category: categoryName(b.categoryId), period: "monthly", limit: b.limit, spent: round(spent), remaining: round(b.limit - spent), percent: round((spent / b.limit) * 100), days_left: daysBetween(on, end) };
    }),
  };
}

function nextDate(dayOfMonth: number, after = TODAY): string {
  const y = Number(after.slice(0, 4));
  const m = Number(after.slice(5, 7));
  const candidate = `${after.slice(0, 7)}-${String(dayOfMonth).padStart(2, "0")}`;
  if (candidate > after) return candidate;
  const nm = m === 12 ? 1 : m + 1;
  const ny = m === 12 ? y + 1 : y;
  return `${ny}-${String(nm).padStart(2, "0")}-${String(dayOfMonth).padStart(2, "0")}`;
}

function listRecurring(input: Input) {
  const kind = str(input, "kind") ?? "all";
  const items = RECURRING.filter((r) => (kind === "all" || r.kind === kind) && (!input.active_only || r.active)).map((r) => ({
    id: r.id, name: r.name, kind: r.kind, type: r.type, amount: r.amount, currency: r.currency,
    amount_base: round(toBase(r.amount, r.currency)), monthly_base: round(toBase(r.amount, r.currency)), frequency: "monthly",
    next_date: nextDate(r.dayOfMonth), category: categoryName(r.categoryId), account: accountName(r.accountId), active: r.active,
  }));
  const monthly = items.filter((i) => i.kind === "subscription" && i.type === "expense").reduce((n, i) => n + i.monthly_base, 0);
  return { currency: BASE_CURRENCY, items, subscriptions_monthly_total_base: round(monthly), missing_rates: [] as string[] };
}

function getInsights() {
  const cafeBudget = getBudgets({}).budgets.find((b) => b.category_id === "cat_cafe")!;
  return {
    health_score: {
      score: 72,
      components: [
        { key: "savings", label: "Сбережения", score: 64 },
        { key: "budgets", label: "Бюджеты", score: 58 },
        { key: "recurring", label: "Регулярные", score: 81 },
        { key: "cushion", label: "Подушка", score: 90 },
        { key: "cashflow", label: "Поток", score: 70 },
      ],
    },
    insights: [
      { id: "ins_cafe_trend", type: "categoryTrend", severity: "warning", title: "Кафе растёт", category_id: "cat_cafe" },
      { id: "ins_cafe_budget", type: "budgetAlert", severity: cafeBudget.percent >= 90 ? "critical" : "warning", title: "Бюджет на кафе", percent: cafeBudget.percent },
      { id: "ins_subs", type: "recurringLoad", severity: "neutral", title: "Подписки", monthly_total: listRecurring({ kind: "subscription" }).subscriptions_monthly_total_base },
    ],
  };
}

function forecastBalance(input: Input) {
  const until = dateArg(input, "until", true)!;
  if (until <= TODAY) throw new ToolInputError("until must be after today");
  const accountIds = list(input, "account_ids")?.length ? list(input, "account_ids")! : ACCOUNTS.filter((a) => a.kind === "regular").map((a) => a.id);
  const start = accountIds.reduce((n, id) => n + toBase(balanceOf(id), ACCOUNTS.find((a) => a.id === id)?.currency ?? "KZT"), 0);
  const obligations = RECURRING.filter((r) => r.type === "expense" && r.active)
    .map((r) => ({ date: nextDate(r.dayOfMonth), label: r.name, amount: toBase(r.amount, r.currency) }))
    .filter((o) => o.date > TODAY && o.date < until)
    .sort((a, b) => a.date.localeCompare(b.date));
  const extras = (Array.isArray(input.extra_changes) ? (input.extra_changes as Input[]) : []).map((c) => ({ date: String(c.date), label: String(c.label), amount: Number(c.amount) }));
  const cushion = typeof input.cushion === "number" ? input.cushion : 0;
  const obligationsTotal = obligations.reduce((n, o) => n + o.amount, 0);
  const extraTotal = extras.filter((e) => e.date > TODAY && e.date < until).reduce((n, e) => n + e.amount, 0);
  const days = daysBetween(TODAY, until);
  const free = start - obligationsTotal - cushion + extraTotal;
  const allowance = free > 0 ? Math.floor(free / days) : 0;
  const series = [];
  let balance = start;
  for (let i = 0; i <= days; i++) {
    const date = new Date(Date.parse(`${TODAY}T00:00:00Z`) + i * 86_400_000).toISOString().slice(0, 10);
    if (i > 0) balance -= allowance;
    balance -= obligations.filter((o) => o.date === date).reduce((n, o) => n + o.amount, 0);
    balance += extras.filter((e) => e.date === date).reduce((n, e) => n + e.amount, 0);
    series.push({ date, balance: round(balance) });
  }
  return {
    currency: BASE_CURRENCY, today: TODAY, until, days, start_balance: round(start), obligations, obligations_total: round(obligationsTotal),
    cushion, extra_changes_total: round(extraTotal), free_amount: round(free), daily_allowance: allowance, series,
  };
}

const KEYWORDS: Record<string, string> = { кофе: "cat_cafe", обед: "cat_cafe", lunch: "cat_cafe", coffee: "cat_cafe", такси: "cat_transport", taxi: "cat_transport", продукты: "cat_groceries", зарплат: "cat_salary", salary: "cat_salary" };

function resolveCategory(value: string | undefined, note?: string): string | null {
  const text = `${value ?? ""} ${note ?? ""}`.toLowerCase();
  const byId = CATEGORIES.find((c) => c.id === value);
  if (byId) return byId.id;
  const byName = CATEGORIES.find((c) => value && c.name.toLowerCase().includes(value.toLowerCase()));
  if (byName) return byName.id;
  for (const [word, id] of Object.entries(KEYWORDS)) if (text.includes(word)) return id;
  return null;
}

function resolveAccount(value: string | null | undefined): string {
  if (!value) return "acc_kaspi";
  const v = value.toLowerCase();
  const byId = ACCOUNTS.find((a) => a.id === value);
  if (byId) return byId.id;
  if (v.includes("usd") || v.includes("доллар") || v.includes("dollar") || v.includes("freedom")) return "acc_usd";
  if (v.includes("депозит") || v.includes("deposit")) return "acc_deposit";
  return "acc_kaspi";
}

let draftSeq = 0;
// The case's language: goal and person names come back in it.
let caseLocale: "ru" | "en" = "ru";
export function resetDrafts(locale: "ru" | "en" = "ru") {
  draftSeq = 0;
  caseLocale = locale;
}

function draftTransactions(input: Input) {
  const items = input.items;
  if (!Array.isArray(items) || items.length === 0) throw new ToolInputError("items must be a non-empty array");
  return {
    draft_id: `draft_${++draftSeq}`,
    items: (items as Input[]).map((item) => {
      const account = resolveAccount(item.account as string | null);
      const category = resolveCategory((item.category as string | null) ?? undefined, (item.note as string | null) ?? undefined);
      return {
        type: item.type, amount: item.amount, currency: (item.currency as string | null) ?? ACCOUNTS.find((a) => a.id === account)!.currency,
        category_id: category, category: category ? categoryName(category) : null, account_id: account, account: accountName(account),
        date: (item.date as string | null) ?? TODAY, note: item.note ?? null,
      };
    }),
    saved: false,
  };
}

function draftBudget(input: Input) {
  const category = resolveCategory(str(input, "category", true));
  if (!category) throw new ToolInputError("unknown category");
  return { draft_id: `draft_${++draftSeq}`, category_id: category, category: categoryName(category), amount: input.amount, period: input.period, previous_limit: BUDGETS.find((b) => b.categoryId === category)?.limit ?? null, saved: false };
}

// As FinanceToolkit.draftRecurring does: a category is required (a subscription takes an
// expense one), next_date is today or later and within a year.
function draftRecurring(input: Input) {
  const kind = str(input, "kind", true);
  if (kind !== "subscription" && kind !== "regular") throw new ToolInputError("kind must be subscription or regular.");
  const name = (str(input, "name", true) ?? "").trim();
  if (!name) throw new ToolInputError("name is required.");
  const amount = optionalNumber(input, "amount");
  if (amount === undefined || amount <= 0) throw new ToolInputError("amount must be positive.");
  const frequency = str(input, "frequency", true)!;
  if (!["daily", "weekly", "monthly", "quarterly", "yearly"].includes(frequency)) throw new ToolInputError("frequency must be daily, weekly, monthly, quarterly or yearly.");
  const next = dateArg(input, "next_date", true)!;
  if (next < TODAY) throw new ToolInputError("next_date cannot be in the past.");
  if (daysBetween(TODAY, next) > 366) throw new ToolInputError("next_date must be within a year.");
  const reference = str(input, "category");
  if (!reference) throw new ToolInputError("Give a category id or name from <app_context>.");
  const candidates = CATEGORIES.filter((c) => kind === "regular" || c.type === "expense");
  const category = candidates.find((c) => c.id === reference) ?? candidates.find((c) => c.name.toLowerCase() === reference.toLowerCase());
  if (!category) throw new ToolInputError(`Unknown category ${reference}. Use a category id from <app_context>.`);
  const accountId = resolveAccount(input.account as string | null);
  return {
    draft_id: `draft_${++draftSeq}`,
    kind,
    name,
    amount: round(amount),
    currency: str(input, "currency")?.toUpperCase() || (ACCOUNTS.find((a) => a.id === accountId)?.currency ?? BASE_CURRENCY),
    frequency,
    next_date: next,
    category_id: category.id,
    category: category.name,
    account_id: accountId,
    account: accountName(accountId),
    guessed: input.account ? [] : ["account"],
    saved: false,
  };
}

function optionalNumber(input: Input, key: string): number | undefined {
  const value = input[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value)) throw new ToolInputError(`${key} must be a number`);
  return value;
}

function planJSON(plan: LoanPlan) {
  return {
    principal: round(plan.principal),
    rate_percent: plan.ratePercent,
    monthly_payment: round(plan.monthlyPayment),
    months_left: plan.monthsLeft,
    total_interest: round(plan.totalInterest),
    total_paid: round(plan.principal + plan.totalInterest),
  };
}

// As FinanceToolkit.simulateLoan does.
function simulateLoan(input: Input) {
  const n = (key: string) => optionalNumber(input, key);
  for (const key of ["rate_percent", "new_rate_percent"]) {
    const v = n(key);
    if (v !== undefined && (v < 0 || v > 100)) throw new ToolInputError(`${key} must be from 0 to 100.`);
  }
  for (const key of ["months_left", "new_months"]) {
    const v = n(key);
    if (v !== undefined && (v < 1 || v > 600 || !Number.isInteger(v))) throw new ToolInputError(`${key} must be from 1 to 600.`);
  }
  for (const key of ["principal", "fees", "extra_monthly", "one_off"]) {
    const v = n(key);
    if (v !== undefined && v < 0) throw new ToolInputError(`${key} cannot be negative.`);
  }
  try {
    const accountId = str(input, "account_id");
    let current: LoanPlan;
    let name: string | null = null;
    if (accountId) {
      const account = ACCOUNTS.find((a) => a.id === accountId);
      if (!account) throw new ToolInputError(`Unknown account ${accountId}.`);
      if (account.kind !== "loan" || account.id !== LOAN_TERMS.accountId) throw new ToolInputError(`Account ${accountId} is not a loan.`);
      name = account.name;
      current = loanPlan(-balanceOf(account.id), LOAN_TERMS.ratePercent, LOAN_TERMS.monthlyPayment, null);
    } else {
      const principal = n("principal");
      const rate = n("rate_percent");
      const months = n("months_left");
      if (!principal || principal <= 0 || rate === undefined || months === undefined) {
        throw new ToolInputError("Give account_id of a loan, or principal, rate_percent and months_left.");
      }
      current = loanPlan(principal, rate, null, months);
    }
    const scenario: LoanScenario = {
      newRatePercent: n("new_rate_percent"),
      newMonths: n("new_months"),
      fees: n("fees") ?? 0,
      extraMonthly: n("extra_monthly") ?? 0,
      oneOff: n("one_off") ?? 0,
      oneOffReducesPayment: str(input, "one_off_mode") === "reduce_payment",
    };
    const base = { currency: BASE_CURRENCY, loan: name, account_id: accountId ?? null, current: planJSON(current), scenario: null };
    const empty = scenario.newRatePercent === undefined && scenario.newMonths === undefined && !scenario.fees && !scenario.extraMonthly && !scenario.oneOff;
    if (empty) return base;
    const after = applyScenario(scenario, current);
    return {
      ...base,
      scenario: { ...planJSON(after), fees: round(scenario.fees) },
      interest_saved: round(current.totalInterest - after.totalInterest - scenario.fees),
      monthly_payment_change: round(after.monthlyPayment - current.monthlyPayment),
      months_saved: current.monthsLeft - after.monthsLeft,
      break_even_months: breakEvenMonths(scenario.fees, current, after),
    };
  } catch (error) {
    if (error instanceof PlanningError) throw new ToolInputError(error.message);
    throw error;
  }
}

// As FinanceToolkit.projectSavings does.
function projectSavings(input: Input) {
  const monthly = optionalNumber(input, "monthly");
  const years = optionalNumber(input, "years");
  const annual = optionalNumber(input, "annual_return_percent");
  if (monthly === undefined || years === undefined || annual === undefined) throw new ToolInputError("monthly, years and annual_return_percent are required");
  const start = optionalNumber(input, "start") ?? 0;
  const inflation = optionalNumber(input, "inflation_percent") ?? null;
  if (!Number.isInteger(years) || years < 1 || years > 50) throw new ToolInputError("years must be from 1 to 50.");
  if (annual < -50 || annual > 50) throw new ToolInputError("annual_return_percent must be from -50 to 50.");
  if (inflation !== null && (inflation < -20 || inflation > 100)) throw new ToolInputError("inflation_percent must be from -20 to 100.");
  if (monthly < 0 || start < 0 || monthly + start <= 0) throw new ToolInputError("monthly and start cannot be negative, and one of them must be above zero.");
  const result = growSavings(start, monthly, annual, years, inflation);
  const [y, m] = [Number(TODAY.slice(0, 4)), TODAY.slice(5, 7)];
  return {
    currency: (str(input, "currency") || BASE_CURRENCY).toUpperCase(),
    years,
    monthly,
    start,
    annual_return_percent: annual,
    inflation_percent: inflation,
    final_amount: round(result.finalAmount),
    contributed: round(result.contributed),
    growth: round(result.finalAmount - result.contributed),
    final_amount_real: result.finalAmountReal === null ? null : round(result.finalAmountReal),
    series: result.years.map((row) => ({ key: `${y + row.year}-${m}`, total: round(row.total), contributed: round(row.contributed) })),
  };
}

// As FinanceToolkit.draftFact does: one short line, a fact id that exists, no text only to
// forget, not remembered already. Both locales' facts share their ids.
function draftFact(input: Input) {
  const replaces = str(input, "replaces") || null;
  const raw = input.text;
  if (raw !== null && raw !== undefined && typeof raw !== "string") throw new ToolInputError("text must be a string or null");
  const text = typeof raw === "string" ? raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).join(" ") : "";
  const all = [...FACTS.ru, ...FACTS.en];
  const previous = replaces ? all.find((f) => f.id === replaces) : undefined;
  if (replaces && !previous) throw new ToolInputError(`There is no fact ${replaces}. Use a fact id from <app_context>.`);
  if (!text) {
    if (!previous) throw new ToolInputError("Give the fact's text, or replaces with the id of the fact to forget.");
    return { draft_id: `draft_${++draftSeq}`, action: "forget", text: null, replaces, previous_text: previous.text, saved: false };
  }
  if (text.length > 200) throw new ToolInputError("Keep a fact under 200 characters: one short sentence.");
  const same = all.find((f) => f.text.toLowerCase() === text.toLowerCase() && f.id !== replaces);
  if (same) throw new ToolInputError(`This is remembered already as ${same.id}.`);
  return { draft_id: `draft_${++draftSeq}`, action: previous ? "change" : "remember", text, replaces, previous_text: previous?.text ?? null, saved: false };
}

// Goals and debts, as FinanceToolkit+Plans.swift does: GoalProgress's months (the current one
// counted, at least 1), a goal with an account follows its balance, new debts need Pro (the
// eval's user has it).
function monthsLeft(deadline: string): number | null {
  if (deadline < TODAY) return null;
  const parts = (date: string) => date.split("-").map(Number) as [number, number, number];
  const [ty, tm, td] = parts(TODAY);
  const [dy, dm, dd] = parts(deadline);
  let months = (dy - ty) * 12 + (dm - tm);
  let days = dd - td;
  if (days < 0) {
    months -= 1;
    days = 1;
  }
  return Math.max(1, months + (days > 0 ? 1 : 0));
}

const goalSaved = (g: (typeof GOALS)[number]) => (g.accountId ? Math.max(0, balanceOf(g.accountId)) : g.contributed);

function goalStatus(g: (typeof GOALS)[number], extra = 0) {
  const saved = goalSaved(g) + extra;
  const reached = saved >= g.target;
  const left = reached ? 0 : g.target - saved;
  const months = g.deadline && !reached ? monthsLeft(g.deadline) : null;
  return { saved, left, reached, months, monthly: months ? round(left / months) : null, overdue: !!g.deadline && !reached && months === null };
}

function getGoals() {
  const goals = GOALS.map((g) => {
    const s = goalStatus(g);
    return {
      id: g.id,
      name: g.name[caseLocale],
      currency: g.currency,
      target: g.target,
      saved: round(s.saved),
      left: round(s.left),
      percent: Math.round(Math.min(1, s.saved / g.target) * 100),
      reached: s.reached,
      deadline: g.deadline,
      months_left: s.months,
      monthly: s.monthly,
      overdue: s.overdue,
      account_id: g.accountId,
      account: g.accountId ? accountName(g.accountId) : null,
    };
  });
  return { goals, total_saved: round(GOALS.reduce((n, g) => n + toBase(goalSaved(g), g.currency), 0)), currency: BASE_CURRENCY };
}

function getDebts() {
  const debts = DEBTS.map((d) => ({
    id: d.id,
    direction: d.direction,
    person: d.person[caseLocale],
    currency: d.currency,
    amount: d.amount,
    repaid: d.repaid,
    remaining: d.amount - d.repaid,
    date: d.date,
    due_date: d.dueDate,
    overdue: !!d.dueDate && d.dueDate < TODAY,
    settled: false,
    settled_on: null,
    note: null,
  }));
  const total = (direction: string) => DEBTS.filter((d) => d.direction === direction).reduce((n, d) => n + toBase(d.amount - d.repaid, d.currency), 0);
  return { debts, owed_to_me: total("owed_to_me"), i_owe: total("i_owe"), currency: BASE_CURRENCY };
}

function positive(input: Input, key: string): number {
  const value = input[key];
  if (typeof value !== "number" || !(value > 0)) throw new ToolInputError(`${key} must be positive.`);
  return value;
}

function pastOrToday(input: Input, key: string): string {
  const date = dateArg(input, key) ?? TODAY;
  if (date > TODAY) throw new ToolInputError(`${key} cannot be in the future.`);
  return date;
}

function draftGoal(input: Input) {
  const name = (str(input, "name", true) ?? "").trim();
  if (!name) throw new ToolInputError("name is required.");
  const target = positive(input, "target");
  const deadline = dateArg(input, "deadline") ?? null;
  if (deadline && deadline < TODAY) throw new ToolInputError("deadline cannot be in the past.");
  const accountRef = str(input, "account");
  const account = accountRef ? ACCOUNTS.find((a) => (a.id === accountRef || a.name.toLowerCase() === accountRef.toLowerCase()) && a.kind !== "loan") : undefined;
  if (accountRef && !account) throw new ToolInputError(`Unknown account ${accountRef}. Use an account id from <app_context> (not a loan).`);
  const already = typeof input.already_saved === "number" ? input.already_saved : 0;
  if (already < 0) throw new ToolInputError("already_saved cannot be negative.");
  if (account && already > 0) throw new ToolInputError("already_saved is for a goal without an account: a goal with an account follows its balance.");
  const currency = str(input, "currency")?.toUpperCase() || account?.currency || BASE_CURRENCY;
  const saved = account ? Math.max(0, balanceOf(account.id)) : already;
  const left = Math.max(0, target - saved);
  const months = deadline && saved < target ? monthsLeft(deadline) : null;
  return {
    draft_id: `draft_${++draftSeq}`,
    name,
    target,
    currency,
    deadline,
    account_id: account?.id ?? null,
    account: account?.name ?? null,
    saved_amount: round(saved),
    left: round(left),
    months_left: months,
    monthly: months ? round(left / months) : null,
    saved: false,
  };
}

function draftGoalContribution(input: Input) {
  const ref = str(input, "goal", true) ?? "";
  const goal = GOALS.find((g) => g.id === ref || g.name.ru.toLowerCase() === ref.toLowerCase() || g.name.en.toLowerCase() === ref.toLowerCase());
  if (!goal) throw new ToolInputError(`Unknown goal ${ref}. Use a goal id from <app_context>.`);
  if (goal.accountId) {
    throw new ToolInputError(`The goal ${goal.name[caseLocale]} follows the balance of the account ${accountName(goal.accountId)}. Money towards it is a transfer to that account: use draft_transactions with type transfer.`);
  }
  const amount = positive(input, "amount");
  const date = pastOrToday(input, "date");
  const after = goalStatus(goal, amount);
  return {
    draft_id: `draft_${++draftSeq}`,
    goal_id: goal.id,
    goal: goal.name[caseLocale],
    amount,
    currency: goal.currency,
    date,
    saved_amount_after: round(after.saved),
    left_after: round(after.left),
    reaches_target: after.reached,
    saved: false,
  };
}

function draftDebt(input: Input) {
  const direction = str(input, "direction", true);
  if (direction !== "owed_to_me" && direction !== "i_owe") throw new ToolInputError("direction must be owed_to_me or i_owe.");
  const person = (str(input, "person", true) ?? "").trim();
  if (!person) throw new ToolInputError("person is required.");
  const amount = positive(input, "amount");
  const date = pastOrToday(input, "date");
  const due = dateArg(input, "due_date") ?? null;
  if (due && due < date) throw new ToolInputError("due_date cannot be before date.");
  return {
    draft_id: `draft_${++draftSeq}`,
    direction,
    person,
    amount,
    currency: str(input, "currency")?.toUpperCase() || BASE_CURRENCY,
    date,
    due_date: due,
    note: str(input, "note") ?? null,
    saved: false,
  };
}

function draftDebtRepayment(input: Input) {
  const ref = (str(input, "debt", true) ?? "").trim();
  const debt =
    DEBTS.find((d) => d.id === ref) ??
    DEBTS.find((d) => d.person.ru.toLowerCase() === ref.toLowerCase() || d.person.en.toLowerCase() === ref.toLowerCase());
  if (!debt) throw new ToolInputError(`No open debt ${ref}. Use a debt id from <app_context>.`);
  const remaining = debt.amount - debt.repaid;
  const amount = input.amount === null || input.amount === undefined ? remaining : positive(input, "amount");
  if (amount > remaining + 0.005) throw new ToolInputError(`That is more than what is left on this debt (${remaining} ${debt.currency}).`);
  return {
    draft_id: `draft_${++draftSeq}`,
    debt_id: debt.id,
    person: debt.person[caseLocale],
    direction: debt.direction,
    amount,
    currency: debt.currency,
    date: pastOrToday(input, "date"),
    remaining_after: round(remaining - amount),
    settles: remaining - amount < 0.005,
    saved: false,
  };
}

// Assets and net worth, as FinanceToolkit+Assets.swift does: AssetValuationMath's gain, growth a
// year (once a year has passed, over 365.25-day years), out of date after six months for homes
// and cars, a year for the rest; NetWorthCalculator's lines. New assets need Pro (the eval's
// user has it); a valuation from an area is multiplied here, never by the model.
const pct = (n: number) => Math.round(n * 10) / 10;

function monthsBefore(date: string, months: number): string {
  const [y, m, d] = date.split("-").map(Number) as [number, number, number];
  const total = y * 12 + (m - 1) - months;
  return `${Math.floor(total / 12)}-${String((total % 12) + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

function assetRow(a: (typeof ASSETS)[number]) {
  const gain = a.purchasePrice === null ? null : a.value - a.purchasePrice;
  const years = a.purchaseDate ? daysBetween(a.purchaseDate, TODAY) / 365.25 : 0;
  const growth = a.purchasePrice && years >= 1 ? (Math.pow(a.value / a.purchasePrice, 1 / years) - 1) * 100 : null;
  const outOfDate = a.valuedOn < monthsBefore(TODAY, a.kind === "other" ? 12 : 6);
  return {
    id: a.id,
    name: a.name[caseLocale],
    kind: a.kind,
    currency: a.currency,
    value: a.value,
    value_base: round(toBase(a.value, a.currency)),
    valued_on: a.valuedOn,
    is_estimate: false,
    out_of_date: outOfDate,
    purchase_price: a.purchasePrice,
    purchase_date: a.purchaseDate,
    gain,
    gain_percent: gain !== null && a.purchasePrice ? pct((gain / a.purchasePrice) * 100) : null,
    annual_growth_percent: growth === null ? null : pct(growth),
    depreciation_percent_a_year: null,
    share_percent: Math.round(a.share * 100),
    owned_value: round(a.value * a.share),
    owned_value_base: round(toBase(a.value * a.share, a.currency)),
    loan_left: null,
    own_money_in_it: null,
    rent_last_12_months: a.rentYear,
    upkeep_last_12_months: a.upkeepYear,
    rental_yield_percent: a.rentYear === null ? null : pct(((a.rentYear - (a.upkeepYear ?? 0)) / a.value) * 100),
    full_result: gain !== null && (a.rentTotal !== null || a.upkeepTotal !== null) ? gain + (a.rentTotal ?? 0) - (a.upkeepTotal ?? 0) : null,
    counted_in_net_worth: true,
    sold: false,
    sold_on: null,
  };
}

function getAssets() {
  const assets = ASSETS.map(assetRow);
  const gain = ASSETS.reduce((n, a) => (a.purchasePrice === null ? n : n + toBase((a.value - a.purchasePrice) * a.share, a.currency)), 0);
  return {
    assets,
    total_base: round(assets.reduce((n, a) => n + a.owned_value_base, 0)),
    gain_base: round(gain),
    currency: BASE_CURRENCY,
    missing_rates: [],
  };
}

const NET_WORTH_LABELS: Record<"ru" | "en", Record<string, string>> = {
  ru: { money: "Деньги на счетах", assets: "Активы", owed_to_me: "Вам должны", loans: "Кредиты", i_owe: "Ваши долги" },
  en: { money: "Money on accounts", assets: "Assets", owed_to_me: "Owed to you", loans: "Loans", i_owe: "Your debts" },
};

function getNetWorth() {
  const accounts = getAccounts().accounts;
  const money = round(accounts.filter((a) => a.kind !== "loan").reduce((n, a) => n + a.balance_base, 0));
  const loans = round(-accounts.filter((a) => a.kind === "loan").reduce((n, a) => n + a.balance_base, 0));
  const assets = round(ASSETS.reduce((n, a) => n + toBase(a.value * a.share, a.currency), 0));
  const left = (direction: string) => round(DEBTS.filter((d) => d.direction === direction).reduce((n, d) => n + toBase(d.amount - d.repaid, d.currency), 0));
  const owedToMe = left("owed_to_me");
  const iOwe = left("i_owe");
  const parts: [string, number][] = [["money", money], ["assets", assets], ["owed_to_me", owedToMe], ["loans", loans], ["i_owe", iOwe]];
  const subtracted = new Set(["loans", "i_owe"]);
  const lines = parts
    .filter(([key, total]) => key === "money" || total > 0)
    .map(([key, total]) => ({ key, label: NET_WORTH_LABELS[caseLocale][key] ?? key, total, subtracted: subtracted.has(key) }));
  return {
    currency: BASE_CURRENCY,
    net_worth: round(money + assets + owedToMe - loans - iOwe),
    money,
    assets,
    owed_to_me: owedToMe,
    loans,
    i_owe: iOwe,
    lines,
    history: [],
    history_note: "The months are not computed yet. Show the lines, not a chart.",
    missing_rates: [],
  };
}

const ASSET_KINDS = ["apartment", "house", "land", "commercial", "vehicle", "other"];

function draftAsset(input: Input) {
  const name = (str(input, "name", true) ?? "").trim();
  if (!name) throw new ToolInputError("name is required.");
  const kind = str(input, "kind", true)!;
  if (!ASSET_KINDS.includes(kind)) throw new ToolInputError(`kind must be one of ${ASSET_KINDS.join(", ")}.`);
  const price = input.purchase_price === null || input.purchase_price === undefined ? null : positive(input, "purchase_price");
  const value = input.value === null || input.value === undefined ? null : positive(input, "value");
  if (price === null && value === null) {
    throw new ToolInputError("Give value (what it is worth now) or purchase_price, or both. If the user said neither, ask them in one sentence instead of drafting.");
  }
  const date = dateArg(input, "purchase_date") ?? null;
  if (date && price === null) throw new ToolInputError("purchase_date goes with purchase_price.");
  if (date && date > TODAY) throw new ToolInputError("purchase_date cannot be in the future.");
  const share = typeof input.share_percent === "number" ? input.share_percent : 100;
  if (!(share > 0 && share <= 100)) throw new ToolInputError("share_percent must be above 0 and at most 100.");
  const loanRef = str(input, "loan_account");
  const loan = loanRef ? ACCOUNTS.find((a) => a.kind === "loan" && (a.id === loanRef || a.name.toLowerCase() === loanRef.toLowerCase())) : undefined;
  if (loanRef && !loan) throw new ToolInputError(`Unknown loan account ${loanRef}. Use a loan account id from <app_context>.`);
  const now = value ?? price!;
  const gain = price === null ? null : now - price;
  const years = date ? daysBetween(date, TODAY) / 365.25 : 0;
  return {
    draft_id: `draft_${++draftSeq}`,
    name,
    kind,
    currency: str(input, "currency")?.toUpperCase() || BASE_CURRENCY,
    value: now,
    purchase_price: price,
    purchase_date: date,
    gain,
    gain_percent: gain !== null && price ? pct((gain / price) * 100) : null,
    annual_growth_percent: price && years >= 1 ? pct((Math.pow(now / price, 1 / years) - 1) * 100) : null,
    share_percent: Math.round(share),
    loan_account_id: loan?.id ?? null,
    saved: false,
  };
}

function draftAssetValuation(input: Input) {
  const ref = (str(input, "asset", true) ?? "").trim();
  const asset = ASSETS.find((a) => a.id === ref || a.name.ru.toLowerCase() === ref.toLowerCase() || a.name.en.toLowerCase() === ref.toLowerCase());
  if (!asset) throw new ToolInputError(`Unknown asset ${ref}. Use an asset id from <app_context>.`);
  let value: number;
  let area: number | null = null;
  let unit: number | null = null;
  if (input.value !== null && input.value !== undefined) {
    value = round(positive(input, "value"));
  } else if (input.area !== null && input.area !== undefined && input.price_per_unit !== null && input.price_per_unit !== undefined) {
    area = positive(input, "area");
    unit = positive(input, "price_per_unit");
    value = round(area * unit);
  } else {
    throw new ToolInputError("Give value, or area and price_per_unit (for example square metres and the price of one in listings). If the user has not said, ask them.");
  }
  const change = value - asset.value;
  return {
    draft_id: `draft_${++draftSeq}`,
    asset_id: asset.id,
    name: asset.name[caseLocale],
    currency: asset.currency,
    value,
    area,
    price_per_unit: unit,
    date: pastOrToday(input, "date"),
    previous_value: asset.value,
    change: round(change),
    change_percent: pct((change / asset.value) * 100),
    gain_after: asset.purchasePrice === null ? null : round(value - asset.purchasePrice),
    note: str(input, "note") ?? null,
    saved: false,
  };
}

// The app's rates: tenge per unit (FinanceToolkit.convertCurrency over CurrencyRateStore).
const RATES: Record<string, number> = { KZT: 1, USD: USD_RATE };

function convertCurrency(input: Input) {
  const from = str(input, "from", true)!.toUpperCase();
  const to = (str(input, "to") ?? BASE_CURRENCY).toUpperCase();
  const amount = input.amount === null || input.amount === undefined ? 1 : Number(input.amount);
  if (!Number.isFinite(amount) || amount < 0) throw new ToolInputError("amount must be zero or more.");
  const fromRate = RATES[from];
  const toRate = RATES[to];
  if (fromRate === undefined || toRate === undefined) throw new ToolInputError(`The app has no exchange rate between ${from} and ${to}. Tell the user so.`);
  const rate = fromRate / toRate;
  return { currency: to, converted: round(amount * rate), rate: Math.round(rate * 1_000_000) / 1_000_000, from: { currency: from, amount: round(amount) }, rates_date: TODAY };
}

const HANDLERS: Record<string, (input: Input) => unknown> = {
  get_spending_summary: spendingSummary,
  compare_periods: comparePeriods,
  search_transactions: searchTransactions,
  get_accounts: getAccounts,
  get_budgets: getBudgets,
  list_recurring: listRecurring,
  get_insights: getInsights,
  forecast_balance: forecastBalance,
  simulate_loan: simulateLoan,
  project_savings: projectSavings,
  draft_transactions: draftTransactions,
  draft_budget: draftBudget,
  draft_recurring: draftRecurring,
  draft_fact: draftFact,
  get_goals: getGoals,
  get_debts: getDebts,
  draft_goal: draftGoal,
  draft_goal_contribution: draftGoalContribution,
  draft_debt: draftDebt,
  draft_debt_repayment: draftDebtRepayment,
  get_assets: getAssets,
  get_net_worth: getNetWorth,
  draft_asset: draftAsset,
  draft_asset_valuation: draftAssetValuation,
  convert_currency: convertCurrency,
};

export function executeTool(name: string, input: Input): unknown {
  const handler = HANDLERS[name];
  if (!handler) throw new ToolInputError(`unknown tool ${name}`);
  return handler(input ?? {});
}

// Direct access for ground truths in cases.
export const simulate = { spendingSummary, comparePeriods, getAccounts, getBudgets, listRecurring, forecastBalance, simulateLoan, projectSavings, getGoals, getDebts, getAssets, getNetWorth, convertCurrency };
