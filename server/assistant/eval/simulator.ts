// Executes the assistant's tools over the synthetic fixture, the way FinanceToolkit does on
// the phone. Simplified (fixed FX rate, monthly budgets only) but deterministic, so the
// grader can compare the model's references with known values.

import {
  ACCOUNTS,
  BASE_CURRENCY,
  BUDGETS,
  CATEGORIES,
  RECURRING,
  TODAY,
  TRANSACTIONS,
  USD_RATE,
  type Transaction,
} from "./fixture";

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
    id: r.id, name: r.name, kind: r.kind, type: r.type, amount: r.amount, currency: r.currency, frequency: "monthly",
    next_date: nextDate(r.dayOfMonth), category: categoryName(r.categoryId), account: accountName(r.accountId), active: r.active,
  }));
  const monthly = items.filter((i) => i.kind === "subscription" && i.type === "expense").reduce((n, i) => n + toBase(i.amount, i.currency), 0);
  return { currency: BASE_CURRENCY, items, subscriptions_monthly_total: round(monthly) };
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
      { id: "ins_subs", type: "recurringLoad", severity: "neutral", title: "Подписки", monthly_total: listRecurring({ kind: "subscription" }).subscriptions_monthly_total },
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
export function resetDrafts() {
  draftSeq = 0;
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

function draftRecurring(input: Input) {
  return { draft_id: `draft_${++draftSeq}`, ...input, account: accountName(resolveAccount(input.account as string | null)), saved: false };
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
  draft_transactions: draftTransactions,
  draft_budget: draftBudget,
  draft_recurring: draftRecurring,
};

export function executeTool(name: string, input: Input): unknown {
  const handler = HANDLERS[name];
  if (!handler) throw new ToolInputError(`unknown tool ${name}`);
  return handler(input ?? {});
}

// Direct access for ground truths in cases.
export const simulate = { spendingSummary, comparePeriods, getAccounts, getBudgets, listRecurring, forecastBalance };
