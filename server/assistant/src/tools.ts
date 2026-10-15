import type Anthropic from "@anthropic-ai/sdk";

// Tool definitions sent to Claude. The phone executes every tool (FinanceToolkit in the
// app) and returns the result; this server only describes them. Names and shapes are the
// contract with the app: changing one needs the matching change in
// Tenra/Services/Agent and a bump of PROTOCOL_VERSION when it is not backwards compatible.
//
// Order is fixed: the tool list is part of the cached prompt prefix.

type Tool = Anthropic.Beta.BetaTool;
type Schema = Tool["input_schema"];

const date = { type: "string", format: "date", description: "YYYY-MM-DD" } as const;
const ids = (what: string) => ({ type: "array", items: { type: "string" }, description: `${what} ids from <app_context>` }) as const;
const nullable = <T extends Record<string, unknown>>(schema: T) => ({ anyOf: [schema, { type: "null" }] });

function object(properties: Record<string, unknown>, required: string[] = []): Schema {
  return { type: "object", properties, required, additionalProperties: false } as Schema;
}

// Strict schemas must list every property as required; optional ones are nullable.
function strictObject(properties: Record<string, unknown>): Schema {
  return object(properties, Object.keys(properties));
}

const readTools: Tool[] = [
  {
    name: "get_spending_summary",
    description:
      "Totals of expenses or income for a date range, computed on the phone with the app's rules (base currency, future-dated operations excluded). Optionally filtered by categories or accounts and grouped by category, merchant, week or month. Use for 'how much did I spend', top categories, month reviews.",
    input_schema: object(
      {
        from: date,
        to: date,
        type: { type: "string", enum: ["expense", "income"] },
        category_ids: ids("Category"),
        account_ids: ids("Account"),
        group_by: { type: "string", enum: ["none", "category", "merchant", "week", "month"] },
      },
      ["from", "to", "type", "group_by"],
    ),
  },
  {
    name: "compare_periods",
    description:
      "Compares expenses or income between two date ranges and returns both totals, the absolute and relative change, and per-group changes. Use for 'compared with last month', 'what changed', 'where did I spend more'.",
    input_schema: object(
      {
        type: { type: "string", enum: ["expense", "income"] },
        current: object({ from: date, to: date }, ["from", "to"]),
        previous: object({ from: date, to: date }, ["from", "to"]),
        group_by: { type: "string", enum: ["none", "category", "merchant"] },
      },
      ["type", "current", "previous", "group_by"],
    ),
  },
  {
    name: "search_transactions",
    description:
      "Finds individual operations by text (merchant or note), date range, type, categories, accounts and amount range. Returns at most `limit` items, newest or largest first.",
    input_schema: object(
      {
        query: { type: "string" },
        from: date,
        to: date,
        type: { type: "string", enum: ["expense", "income", "transfer", "any"] },
        category_ids: ids("Category"),
        account_ids: ids("Account"),
        min_amount: { type: "number" },
        max_amount: { type: "number" },
        sort: { type: "string", enum: ["newest", "largest"] },
        limit: { type: "integer", description: "1 to 50" },
      },
      ["type", "sort", "limit"],
    ),
  },
  {
    name: "get_accounts",
    description:
      "All accounts with their current balance, currency and kind (regular, deposit, loan), plus the total in the base currency.",
    input_schema: object({}),
  },
  {
    name: "get_budgets",
    description:
      "Category budgets with limit, spent, remaining, period and days left in the period, as of a date (today by default).",
    input_schema: object({ on_date: date }),
  },
  {
    name: "list_recurring",
    description:
      "Subscriptions and other recurring payments with amount, frequency, next charge date and status.",
    input_schema: object(
      {
        kind: { type: "string", enum: ["subscription", "all"] },
        active_only: { type: "boolean" },
      },
      ["kind", "active_only"],
    ),
  },
  {
    name: "get_insights",
    description:
      "The app's current insights (spending trends, budget alerts, recurring load, cash flow, savings rate, forecast) and the 0-100 financial health score with its components.",
    input_schema: object(
      {
        category: {
          type: "string",
          enum: ["all", "spending", "income", "budget", "recurring", "cashflow", "wealth", "savings", "forecasting", "health"],
        },
      },
      ["category"],
    ),
  },
  {
    name: "forecast_balance",
    description:
      "Projects the balance from today to a date: daily series, known obligations (loan payments, subscriptions, recurring payments) and, after keeping an optional cushion, the free amount and the daily allowance. Optional extra changes simulate 'what if I set aside 50 000 on the 1st'.",
    input_schema: object(
      {
        until: date,
        cushion: { type: "number", description: "Amount to keep untouched, base currency" },
        account_ids: ids("Account"),
        extra_changes: {
          type: "array",
          items: object(
            { label: { type: "string" }, amount: { type: "number", description: "Negative for outflow" }, date },
            ["label", "amount", "date"],
          ),
        },
      },
      ["until"],
    ),
  },
  {
    name: "simulate_loan",
    description:
      "Loan what-if, computed on the phone: what a loan costs from today (monthly payment, months left, total interest) and, when a scenario is given, the same after refinancing at a new rate or term with one-off fees, with an extra payment every month, or with an early repayment now. Returns the net interest saved (after fees), the change in the monthly payment, months saved and the months it takes the lower payment to pay back the fees. Pass account_id for a loan from <app_context>, or principal, rate_percent and months_left for a loan the user describes. Leave the scenario fields out to see the loan as it runs.",
    input_schema: object({
      account_id: { type: "string", description: "Loan account id from <app_context>" },
      principal: { type: "number", description: "Loan not in the app: what is left to repay" },
      rate_percent: { type: "number", description: "Loan not in the app: annual interest rate, %" },
      months_left: { type: "integer", description: "Loan not in the app: months left" },
      new_rate_percent: { type: "number", description: "Refinancing: new annual rate, %" },
      new_months: { type: "integer", description: "Refinancing: new term in months" },
      fees: { type: "number", description: "Refinancing: one-off costs paid up front" },
      extra_monthly: { type: "number", description: "Paid on top of the payment every month" },
      one_off: { type: "number", description: "Early repayment now" },
      one_off_mode: { type: "string", enum: ["reduce_term", "reduce_payment"], description: "What the early repayment lowers; reduce_term by default" },
    }),
  },
  {
    name: "project_savings",
    description:
      "Compound growth of regular saving or investing: a starting amount, a monthly contribution and an annual return over a number of years. Returns the final amount, what was put in, the growth, the final amount in today's money when inflation is given, and a yearly series for a chart (path series). The return is an assumption (the user's, or one you state as an example), never a forecast.",
    input_schema: object(
      {
        monthly: { type: "number", description: "Put in at the end of every month" },
        years: { type: "integer", description: "1 to 50" },
        annual_return_percent: { type: "number", description: "Assumed yearly return, %" },
        start: { type: "number", description: "Amount at the start" },
        inflation_percent: { type: "number", description: "Yearly inflation, % (for today's money)" },
        currency: { type: "string", description: "ISO 4217; the base currency by default" },
      },
      ["monthly", "years", "annual_return_percent"],
    ),
  },
  {
    name: "get_goals",
    description:
      "The user's savings goals: target, saved so far (a linked account's balance, or the money they marked towards it), what is left, percent, deadline, months left and what to put aside each month to make it, reached or overdue, plus everything saved in the base currency.",
    input_schema: object({}),
  },
  {
    name: "get_debts",
    description:
      "Personal debts between the user and people they know (not bank loans): open ones both ways (owed_to_me, i_owe) with amount, repaid, remaining, date, due date and overdue, the latest settled ones, and the open totals each way in the base currency.",
    input_schema: object({}),
  },
];

// The API compiles every strict schema into one grammar and refuses a request whose strict
// tools have more than 16 parameters with a union type (a nullable is one), failing every
// turn: the goal and debt drafts are not strict, their optional fields simply left out
// (tools.test.ts holds the count).
const draftTools: Tool[] = [
  {
    name: "draft_transactions",
    description:
      "Prepares one or more operations as a draft for the user to confirm. Nothing is saved. Category and account accept an id or a name; the phone resolves names and fills gaps from the user's history. Returns draft_id and the resolved fields.",
    strict: true,
    input_schema: strictObject({
      items: {
        type: "array",
        items: strictObject({
          type: { type: "string", enum: ["expense", "income", "transfer"] },
          amount: { type: "number" },
          currency: nullable({ type: "string", description: "ISO 4217; null for the account's currency" }),
          category: nullable({ type: "string" }),
          account: nullable({ type: "string" }),
          to_account: nullable({ type: "string", description: "Transfers only" }),
          date: nullable(date),
          note: nullable({ type: "string" }),
        }),
      },
    }),
  },
  {
    name: "draft_budget",
    description: "Prepares a new or changed category budget for the user to confirm. Nothing is saved.",
    strict: true,
    input_schema: strictObject({
      category: { type: "string", description: "Category id or name" },
      amount: { type: "number" },
      period: { type: "string", enum: ["weekly", "monthly", "yearly"] },
    }),
  },
  {
    name: "draft_recurring",
    description:
      "Prepares a subscription (a service like Netflix) or a regular payment (rent, a loan payment, a salary) for the user to confirm. Nothing is saved. next_date is the next charge, today or later; category is a category id or name (a subscription takes an expense category); account defaults to the one the history suggests.",
    strict: true,
    input_schema: strictObject({
      kind: { type: "string", enum: ["subscription", "regular"] },
      name: { type: "string" },
      amount: { type: "number" },
      currency: nullable({ type: "string" }),
      frequency: { type: "string", enum: ["daily", "weekly", "monthly", "quarterly", "yearly"] },
      next_date: date,
      category: nullable({ type: "string" }),
      account: nullable({ type: "string" }),
    }),
  },
  {
    name: "draft_fact",
    description:
      "Prepares a fact about the user's money to remember across chats (payday, the main account, a goal they save for, money they owe or are owed), or a change to or the removal of a fact you remember. Nothing is kept until the user taps Save on the confirm block. replaces is the id of a remembered fact from <app_context> to change or forget; text is the fact as one short sentence in the user's language, or null together with replaces to forget it.",
    strict: true,
    input_schema: strictObject({
      text: nullable({ type: "string", description: "One short sentence, under 200 characters" }),
      replaces: nullable({ type: "string", description: "Id of a remembered fact, e.g. f2" }),
    }),
  },
  {
    name: "draft_goal",
    description:
      "Prepares a new savings goal for the user to confirm. Nothing is saved. With account (an account id or name, not a loan) the goal follows that account's balance; without one, already_saved is what the user has put aside so far and later money is added with draft_goal_contribution. currency defaults to the account's, else the base currency. Returns draft_id, what is saved, what is left and, with a deadline, months_left and monthly.",
    input_schema: object(
      {
        name: { type: "string", description: "What the user saves for, short, in their language" },
        target: { type: "number" },
        currency: { type: "string" },
        deadline: date,
        account: { type: "string" },
        already_saved: { type: "number" },
      },
      ["name", "target"],
    ),
  },
  {
    name: "draft_goal_contribution",
    description:
      "Prepares money the user put towards a goal without an account, in the goal's currency, for them to confirm. Nothing is saved. goal is a goal id from <app_context>. A goal with an account grows with that account: draft a transfer to it with draft_transactions instead.",
    input_schema: object(
      {
        goal: { type: "string" },
        amount: { type: "number" },
        date,
        note: { type: "string" },
      },
      ["goal", "amount"],
    ),
  },
  {
    name: "draft_debt",
    description:
      "Prepares a personal debt for the user to confirm: money they lent to someone (owed_to_me) or borrowed from someone (i_owe). Nothing is saved. Not for bank loans. Personal debts are Tenra Pro: without it the tool says so.",
    input_schema: object(
      {
        direction: { type: "string", enum: ["owed_to_me", "i_owe"] },
        person: { type: "string", description: "Who, as the user names them" },
        amount: { type: "number" },
        currency: { type: "string" },
        date,
        due_date: date,
        note: { type: "string" },
      },
      ["direction", "person", "amount"],
    ),
  },
  {
    name: "draft_debt_repayment",
    description:
      "Prepares money back on an open debt, in its currency, for the user to confirm. Nothing is saved. debt is a debt id from <app_context>; leave amount out for everything that is left, which settles the debt.",
    input_schema: object(
      {
        debt: { type: "string" },
        amount: { type: "number" },
        date,
        note: { type: "string" },
      },
      ["debt"],
    ),
  },
];

const source = { type: "string", description: "result_id of the tool result that holds the data, e.g. r1" };
const path = { type: "string", description: "Dotted path inside that result, e.g. total or groups" };

const block = (type: string, properties: Record<string, unknown>) =>
  strictObject({ type: { type: "string", const: type }, ...properties });

export const RENDER_REPLY = "render_reply";
// What the app answers a render_reply sent next to other tool calls (AgentProtocol in
// Tenra/Services/Agent/AgentWire.swift); the eval sends the same.
export const RENDER_REPLY_TOO_EARLY =
  "render_reply was called together with other tools, before their results existed, so nothing was shown. Call render_reply again, alone, pointing at the results above.";

// Not strict: the API compiles strict schemas into one grammar and refuses this block union
// ("compiled grammar is too large"), failing every request. The app decodes each block on
// its own and shows nothing for one it cannot read (AgentReply.swift); the eval's
// blocks_decode check holds the models to the schema.
const renderReply: Tool = {
  name: RENDER_REPLY,
  // The reply streams to the app as it is written (index.ts, event "reply"): without this the
  // API buffers each key-value pair, so a text block would arrive whole.
  eager_input_streaming: true,
  description:
    "Shows your reply. Call exactly once, last, every turn. Blocks render top to bottom as native app cards; figures come from tool results by reference, never from text.",
  input_schema: strictObject({
    blocks: {
      type: "array",
      items: {
        anyOf: [
          block("text", { text: { type: "string", description: "Markdown: short sentences, **bold** for the key point, \"- \" bullets or \"1. \" steps, an optional \"### \" heading. No money amounts." } }),
          block("metric", { label: { type: "string" }, source, path, trend_path: nullable({ type: "string" }) }),
          block("chart", { kind: { type: "string", enum: ["bar", "line", "donut"] }, title: { type: "string" }, source, path }),
          block("transactions", { title: nullable({ type: "string" }), source }),
          block("budgets", { source, category_ids: nullable({ type: "array", items: { type: "string" } }) }),
          block("recurring", { source }),
          block("forecast", { source }),
          block("insight", { source, insight_id: { type: "string" } }),
          block("confirm", { draft_id: { type: "string" } }),
          block("open", {
            destination: { type: "string", enum: ["category", "account", "analytics", "history", "budgets", "subscriptions"] },
            target_id: nullable({ type: "string" }),
            label: { type: "string" },
          }),
        ],
      },
    },
    mood: { type: "string", enum: ["idle", "happy", "concerned", "celebrate"] },
    suggestions: { type: "array", items: { type: "string" } },
  }),
};

export const TOOLS: Tool[] = [...readTools, ...draftTools, renderReply];
export const TOOL_NAMES: ReadonlySet<string> = new Set(TOOLS.map((t) => t.name));
export const DRAFT_TOOLS: ReadonlySet<string> = new Set(draftTools.map((t) => t.name));
