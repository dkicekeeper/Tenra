import type Anthropic from "@anthropic-ai/sdk";
import type { Config } from "./config";
import type { Tier } from "./quota";

// Tool definitions sent to Claude. The phone executes every tool (FinanceToolkit in the
// app) and returns the result; this server only describes them. Names and shapes are the
// contract with the app: changing one needs the matching change in
// Tenra/Services/Agent and a bump of PROTOCOL_VERSION when it is not backwards compatible.
//
// Order is fixed: the tool list is part of the cached prompt prefix.

type Tool = Anthropic.Beta.BetaTool;

/** Values an asset from listings (POST /v1/valuation through the phone); offered while that is on. */
export const ESTIMATE_ASSET_VALUE = "estimate_asset_value";
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
      "All accounts with their current balance, currency and kind (regular, deposit, loan), each balance in the base currency too (balance_base), plus the total in the base currency. Show the total as a metric block (path total_base); never write it in the text, not even rounded.",
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
      "Subscriptions and other recurring payments with amount in their own currency and in the base currency (amount_base, and monthly_base for a month), frequency, next charge date and status, plus what the active subscriptions cost a month in the base currency (subscriptions_monthly_total_base), payments in other currencies included.",
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
      "Projects the balance from today to a date: daily series, known obligations (loan payments, subscriptions, recurring payments) and, after keeping an optional cushion, the free amount and the daily allowance. Optional extra changes simulate 'what if I set aside 50 000 on the 1st'. Show the free amount, the daily allowance and how they change as metric blocks from this result; never write these figures in the text.",
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
      "Loan what-if, computed on the phone: what a loan costs from today (monthly payment, months left, total interest) and, when a scenario is given, the same after refinancing at a new rate or term with one-off fees, with an extra payment every month, or with an early repayment now. Returns the net interest saved (after fees), the change in the monthly payment, months saved and the months it takes the lower payment to pay back the fees. Pass account_id for a loan from <app_context>, or principal, rate_percent and months_left for a loan the user describes. Leave the scenario fields out to see the loan as it runs. Show what you cite (the saving, the payment, the interest) as metric blocks from this result; never write these figures in the text.",
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
      "Compound growth of regular saving or investing: a starting amount, a monthly contribution and an annual return over a number of years. Returns the final amount, what was put in, the growth, the final amount in today's money when inflation is given, and a yearly series for a chart (path series). The return is an assumption (the user's, or one you state as an example), never a forecast. Show the final amount, what was put in and the growth as metric blocks from this result; never write them, or sums you work out from the inputs, in the text.",
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
      "The user's savings goals: target, saved so far (a linked account's balance, or the money they marked towards it), what is left, percent, deadline, months left and what to put aside each month to make it, reached or overdue, saved and left in the base currency too (saved_base, left_base), plus everything saved in the base currency.",
    input_schema: object({}),
  },
  {
    name: "find_recurring_candidates",
    description:
      "Looks through the last year of expenses for payments that repeat like a subscription or a regular payment and are not one in the app yet: the same merchant at even intervals (weekly, monthly, quarterly, yearly) for about the same amount. Returns up to 10 candidates with the name, amount, currency, frequency, how many times, the last date, the next expected date, the category and the account. Use it when the user asks to find their subscriptions or regular payments in the history; offer draft_recurring for the ones they pick.",
    input_schema: object({}),
  },
  {
    name: "get_cleanup_overview",
    description:
      "How much there is to tidy in the user's data, by part, in one call: on_review (payments recorded by themselves with a guess nobody looked at), review_questions_on_screen, duplicate_groups (records that look entered twice), categories_unused (never used), categories_idle (not used for a year), records_without_category (their category no longer exists) and subscriptions_missed (active subscriptions with no charge for a long time). Use it for the monthly tidy-up; each part has its own tool for the details.",
    input_schema: object({}),
  },
  {
    name: "get_merchants",
    description:
      "The merchants of the last twelve months of expenses, for tidying them: up to 40, the most used first, each with merchant (its name), records, total in the base currency, categories (where its records went, with counts: more than one means it is split), remembered_category (the category a payment there gets when it records itself; null when none is remembered) and brand (the brand it is joined into, or null); merchants_total; and look_alike: groups of merchants whose names start with the same word and are not one brand yet (maybe points of one brand).",
    input_schema: object({}),
  },
  {
    name: "get_subscription_audit",
    description:
      "Each subscription with its real charges, for looking them over: amount, currency, frequency, active, charges_total, last_charge, days_since_last_charge, recent_charges (up to 4, newest first), price_change_percent (between the last two charges, null when it did not change), missed (an active subscription with no charge for an interval and a half: probably cancelled or forgotten) and same_name_as (other subscriptions with the same name: probably entered twice). Read only: pausing is draft_subscription_state, the amount and cancelling are on the subscription's screen.",
    input_schema: object({}),
  },
  {
    name: "suggest_budgets",
    description:
      "What each expense category took in each of the last three whole months, in the base currency, next to the monthly budget it has: months (month, spent), average, highest, limit (null without a monthly budget), months_over (how many of the three went over the limit) and other_period (it has a weekly or yearly budget: leave it). Largest first. Use it to offer budgets that follow what is really spent; the limits themselves go through draft_budget.",
    input_schema: object({}),
  },
  {
    name: "find_duplicates",
    description:
      "Looks through the last twelve months for incomes and expenses that look recorded twice: the same day, type, amount and currency on the same account (what a statement imported over payments that recorded themselves leaves behind). Returns up to 20 groups, newest first, each with date, amount, currency, same_merchant (every record has the same name: almost surely one payment twice) and its records (transaction_id, merchant, category, account, recurring), and count_total. Two real payments of the same amount on one day are possible: the user decides. Offer draft_transaction_delete for the extra record of each group they confirm, keeping the one with the better name and category.",
    input_schema: object({}),
  },
  {
    name: "get_category_audit",
    description:
      "How the user's categories and subcategories are used over the last twelve months, for tidying them up. Per expense and income category: records, their total in the base currency and share_percent of its type, last_date, unused (no record ever), idle (none in these twelve months), has_budget, top_merchants (up to 5 with their record counts), its subcategories with their record counts and without_subcategory (records tagged with none, when the category has subcategories); apart, without_category: records whose category no longer exists. Categories come largest first.",
    input_schema: object({}),
  },
  {
    name: "get_review_queue",
    description:
      "The payments on review: the ones Apple Pay and bank notifications recorded by themselves with a category or an account Tenra guessed, which the user has not looked at yet. Returns up to 30, newest first, with transaction_id, date, merchant, amount, currency, the category and account they were saved with and what was guessed (category, account), the total on review, and questions_on_screen: charges that may belong to a subscription and pairs that may be a transfer between own accounts, which are answered on the To review screen (an open block with the destination review).",
    input_schema: object({}),
  },
  {
    name: "get_loans",
    description:
      "The user's loans and installment plans with their terms: what is left to repay, the original amount, the yearly rate, the monthly payment and its day, the term, payments made and left, the end date, the last payment and the interest paid so far. Use it for questions about a loan's terms; simulate_loan works out refinancing and early repayment.",
    input_schema: object({}),
  },
  {
    name: "get_deposits",
    description:
      "The user's deposits with their terms: the balance, the yearly rate, whether interest is added to the deposit (capitalization), the day interest is posted, the interest accrued since the last posting and the start date.",
    input_schema: object({}),
  },
  {
    name: "get_debts",
    description:
      "Personal debts between the user and people they know (not bank loans): open ones both ways (owed_to_me, i_owe) with amount, repaid, remaining (and remaining_base in the base currency), date, due date and overdue, the latest settled ones, and the open totals each way in the base currency.",
    input_schema: object({}),
  },
  {
    name: "get_assets",
    description:
      "What the user owns (Finances, Assets): homes, land, cars and other things, the held ones and the latest sold. Each with its value now (the latest valuation, or the purchase price; is_estimate when a yearly depreciation the user set counts it down), valued_on and out_of_date (a valuation older than six months for homes and cars, a year for other things), the purchase price and date, the gain and gain_percent since the purchase, annual_growth_percent, value_in_3_years (with a yearly depreciation the user set, what it will be worth in three years at that rate), share_percent and owned_value (owned_value_base in the base currency), loan_left and own_money_in_it with a linked loan, rent_last_12_months, upkeep_last_12_months, rental_yield_percent ((rent minus upkeep) over the value) and full_result (the gain plus all rent minus all upkeep since the purchase). Plus total_base, what the held assets counted in net worth come to, and gain_base.",
    input_schema: object({}),
  },
  {
    name: "get_net_worth",
    description:
      "Net worth, computed on the phone as the app's net worth insight: money on the accounts plus the assets at the user's share plus what others owe them, minus what is left of the loans and what they owe, all in the base currency. Fields net_worth, money, assets, owed_to_me, loans and i_owe for metrics; lines (key, label, total, subtracted) for a chart of its parts; history, net worth at the end of each of the last months, for a line chart when it is not empty.",
    input_schema: object({}),
  },
  {
    name: ESTIMATE_ASSET_VALUE,
    description:
      "Estimates what one of the user's assets is worth now from listings of comparable ones for sale, found by a web search on the server; the median and the range of their asking prices are computed in code, never by you. Takes up to a minute and counts against a monthly limit: call it once per question, with what the kind needs. The characteristics saved on the asset (get_assets) go with it on their own: pass what the user said. asset is an asset id from <app_context>. A flat or commercial property: city, district, area_m2, rooms (as the country's listings count them), and when known year_built, building, floor, floors, condition, complex. A house: city or region, area_m2, land_ares. Land: city or region, land_ares (a sotka is an are), land_use, utilities. A vehicle: make, model, year, mileage_km, and when known generation, engine_l, fuel, transmission, customs_cleared. Other things: description. country is ISO 3166 (the user's by default). Returns status (ok, or insufficient when too few comparable listings were found), value_in_asset_currency, low_in_asset_currency and high_in_asset_currency (the asset's currency), the same in the market's currency (value, low, high, market_currency), current_value and change_percent against it, count (listings used), accuracy (high, medium or low), sites, and estimates_left this month.",
    input_schema: object(
      {
        asset: { type: "string" },
        country: { type: "string", description: "ISO 3166-1 alpha-2, for example KZ; the user's by default" },
        city: { type: "string" },
        region: { type: "string" },
        district: { type: "string" },
        complex: { type: "string", description: "A residential complex or a building's name" },
        area_m2: { type: "number", description: "Floor area in square metres" },
        rooms: { type: "integer" },
        year_built: { type: "integer" },
        building: { type: "string", enum: ["panel", "brick", "monolith", "block", "wood", "other"] },
        floor: { type: "integer" },
        floors: { type: "integer" },
        condition: { type: "string", enum: ["rough", "needs_repair", "standard", "good", "excellent"] },
        land_ares: { type: "number", description: "Land in ares: one sotka is one are" },
        land_use: { type: "string", enum: ["residential", "garden", "farm", "commercial", "other"] },
        utilities: { type: "array", items: { type: "string", enum: ["gas", "water", "sewer", "electricity"] } },
        commercial_type: { type: "string", enum: ["office", "retail", "warehouse", "other"] },
        make: { type: "string" },
        model: { type: "string" },
        generation: { type: "string" },
        year: { type: "integer", description: "A vehicle's model year" },
        engine_l: { type: "number" },
        fuel: { type: "string", enum: ["petrol", "diesel", "hybrid", "electric", "gas", "other"] },
        transmission: { type: "string", enum: ["automatic", "manual"] },
        drive: { type: "string", enum: ["fwd", "rwd", "awd"] },
        mileage_km: { type: "number" },
        customs_cleared: { type: "boolean", description: "Kazakhstan: registered in the country" },
        steering: { type: "string", enum: ["left", "right"] },
        description: { type: "string", description: "What the thing is, for other things" },
      },
      ["asset"],
    ),
  },
  {
    name: "convert_currency",
    description:
      "Converts an amount from one currency to another (the base currency by default) at the exchange rates the app converts everything with, computed on the phone. Returns the converted amount (path converted), the rate for one unit (path rate) and the day the app last updated its rates (rates_date). It is the app's reference rate for the day, the same for every user, not a bank's buy or sell rate. Use for 'what is the dollar rate' (convert 1 from USD) or 'how much is 100 euros in tenge'.",
    input_schema: object(
      {
        amount: { type: "number", description: "1 by default" },
        from: { type: "string", description: "ISO 4217, for example USD" },
        to: { type: "string", description: "ISO 4217; the base currency by default" },
      },
      ["from"],
    ),
  },
];

// The API compiles every strict schema into one grammar and refuses a request whose strict
// tools have more than 16 parameters with a union type (a nullable is one), failing every
// turn: the goal, debt and asset drafts are not strict, their optional fields simply left out
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
    name: "draft_transaction_edit",
    description:
      "Prepares a change to one saved income or expense for the user to confirm: a new amount, category, date or note. Nothing changes until they confirm on the card, which shows the record as it is and as it becomes. transaction_id is an id from search_transactions; give only the fields that change, null for the rest. A transfer and a record of a loan or a deposit are refused (they are changed in History). Returns draft_id, before and after.",
    strict: true,
    input_schema: strictObject({
      transaction_id: { type: "string" },
      amount: nullable({ type: "number" }),
      category: nullable({ type: "string", description: "Category id or name, of the record's own type" }),
      date: nullable(date),
      note: nullable({ type: "string" }),
    }),
  },
  {
    name: "draft_transaction_delete",
    description:
      "Prepares the deletion of saved incomes or expenses for the user to confirm, at most 20 in one draft. Nothing is deleted until they confirm on the card, which lists every record. transaction_ids are ids from search_transactions. A transfer and a record of a loan or a deposit come back under skipped. Returns draft_id, count, items and skipped.",
    strict: true,
    input_schema: strictObject({
      transaction_ids: { type: "array", items: { type: "string" } },
    }),
  },
  {
    name: "draft_recategorize",
    description:
      "Prepares moving every saved income or expense of one merchant to another category, as one draft for the user to confirm (at most 50 records; narrow the period for more). Nothing changes until they confirm on the card, which lists the records. merchant is text from the merchant's name as records carry it (check with search_transactions when unsure); category is the target category id or name; from and to bound the period; leave them out for all time. Returns draft_id, count, the categories the records leave and the first record.",
    // Not strict: the API allows 16 union-typed parameters across the strict tools, and they are taken.
    input_schema: object(
      {
        merchant: { type: "string" },
        category: { type: "string", description: "Target category id or name" },
        from: date,
        to: date,
      },
      ["merchant", "category"],
    ),
  },
  {
    name: "draft_subscription_state",
    description:
      "Prepares pausing a subscription (no charges are recorded until it is resumed) or resuming a paused one, for the user to confirm on the card. subscription is an id from list_recurring or the subscription's name. Its amount, its date and cancelling it are done on the subscription's own screen. Returns draft_id.",
    input_schema: object(
      {
        subscription: { type: "string" },
        action: { type: "string", enum: ["pause", "resume"] },
      },
      ["subscription", "action"],
    ),
  },
  {
    name: "draft_category_change",
    description:
      "Prepares one change to a category, for the user to confirm on the card: a new name (name; its records follow), folding it into another category of the same type (merge_into: its records, subscriptions and remembered merchants move there and it is deleted, its own budget goes with it), or deleting a category no record uses (delete true; one with records is refused: merge it instead). Exactly one of name, merge_into and delete. category and merge_into are category ids from <app_context> or names. One draft per category. To move only some records to another category use draft_recategorize. Returns draft_id, action, records and budget_lost.",
    input_schema: object(
      {
        category: { type: "string" },
        name: { type: "string", description: "The new name, up to 40 characters" },
        merge_into: { type: "string", description: "The category that takes the records" },
        delete: { type: "boolean" },
      },
      ["category"],
    ),
  },
  {
    name: "draft_merchant_rule",
    description:
      "Prepares a rule for a merchant, for the user to confirm on the card: from now on a payment there that records itself (Apple Pay, a bank notification) gets this expense category. It does not move the records already saved: records_in_other_categories says how many sit elsewhere, and draft_recategorize moves them. merchant is a name from get_merchants; category is an expense category id from <app_context> or its name. Returns draft_id.",
    input_schema: object(
      {
        merchant: { type: "string" },
        category: { type: "string" },
      },
      ["merchant", "category"],
    ),
  },
  {
    name: "draft_merchant_brand",
    description:
      "Prepares joining points of one brand that the bank names apart (\"ZARA MEGA\" and \"ZARA DOSTYK\") into one merchant, for the user to confirm on the card: its screen then shows every point's records together. Nothing in the records changes. merchants are 2 to 10 names from get_merchants (its look_alike groups are candidates); name is the brand's name, optional. A merchant already in a brand is refused: brands are changed on the merchant's screen. Returns draft_id.",
    input_schema: object(
      {
        merchants: { type: "array", items: { type: "string" } },
        name: { type: "string" },
      },
      ["merchants"],
    ),
  },
  {
    name: "draft_reminder",
    description:
      "Prepares a one-off reminder for the user to confirm on the card: at the day and time a notification on their phone shows text. date is YYYY-MM-DD, today or later and at most a year ahead; time is HH:MM in 24 hours, 10:00 by default; text is the reminder in the user's language, short (\"Pay the rent\"). For a payment that repeats, a subscription or a regular payment (draft_recurring) reminds before each charge. Returns draft_id.",
    input_schema: object(
      {
        text: { type: "string" },
        date: { type: "string", description: "YYYY-MM-DD" },
        time: { type: "string", description: "HH:MM" },
      },
      ["text", "date"],
    ),
  },
  {
    name: "draft_spending_reminder",
    description:
      "Prepares turning the evening spending reminder on or off, or moving it to another time, for the user to confirm on the card. It comes only on days with nothing recorded. time is HH:MM; without it the time stays. Returns draft_id, on, time and was_on.",
    input_schema: object(
      {
        on: { type: "boolean" },
        time: { type: "string", description: "HH:MM" },
      },
      ["on"],
    ),
  },
  {
    name: "draft_account_change",
    description:
      "Prepares a new name for an account, or whether it counts in the total balance on Home (in_total), for the user to confirm on the card. account is an account id from <app_context> or its name. Its balance, currency and kind are changed on the account's screen; the balance can also be set with draft_balance_correction. Returns draft_id.",
    input_schema: object(
      {
        account: { type: "string" },
        name: { type: "string", description: "Up to 40 characters" },
        in_total: { type: "boolean" },
      },
      ["account"],
    ),
  },
  {
    name: "draft_feedback",
    description:
      "Prepares the user's words for the developer of Tenra, for them to send from the card (its button is Send). Use it when the user asks to pass something on to the developer or the team, to leave feedback, to report a problem or to suggest a feature. text is what they want said, in their own words and language, without changes beyond joining their messages; mood is good for praise, bad for a complaint, omitted otherwise. Nothing is sent until they press Send. Returns draft_id.",
    input_schema: object(
      {
        text: { type: "string", description: "Up to 2000 characters" },
        mood: { type: "string", enum: ["good", "bad"] },
      },
      ["text"],
    ),
  },
  {
    name: "draft_balance_correction",
    description:
      "Prepares setting an everyday account to the balance the bank shows, for the user to confirm on the card. The account's starting balance takes the difference: no income or expense is made up and the statistics do not change. Use it only after the user gives the real balance and no missing record explains the difference, or when they just want the balance set. Not for loans and deposits. account is an account id from <app_context> or its name; balance is in the account's currency. Returns draft_id, before, after and difference.",
    input_schema: object(
      {
        account: { type: "string" },
        balance: { type: "number", description: "What the account really holds" },
      },
      ["account", "balance"],
    ),
  },
  {
    name: "draft_subcategory",
    description:
      "Prepares a subcategory inside a category, for the user to confirm on the card: it is created when the category does not have it yet, and with merchant given every record of that category whose name contains it (up to 300) is tagged with it, keeping the tags it has. category is a category id from <app_context> or a name; merchant is a name from get_category_audit's top_merchants or search_transactions. Returns draft_id, new, records and records_left.",
    input_schema: object(
      {
        category: { type: "string" },
        name: { type: "string", description: "The subcategory's name, up to 40 characters" },
        merchant: { type: "string", description: "Tag this merchant's records in the category" },
      },
      ["category", "name"],
    ),
  },
  {
    name: "draft_review_confirm",
    description:
      "Prepares confirming payments on review that are right as they were saved, for the user to confirm on one card: they leave the review list, the category is remembered for the merchant and the account for the card, so the next payment there is not a guess. Give transaction_ids from get_review_queue, or all true for every payment on review. A payment whose category is wrong is not confirmed: fix it with draft_transaction_edit, which takes it off review when saved. Returns draft_id, count and left_on_review.",
    input_schema: object(
      {
        transaction_ids: { type: "array", items: { type: "string" }, description: "From get_review_queue, up to 30" },
        all: { type: "boolean", description: "Every payment on review" },
      },
      [],
    ),
  },
  {
    name: "draft_goal_change",
    description:
      "Prepares a change to a savings goal the user already has, for them to confirm: a new name, target or deadline. Nothing changes until they confirm on the card, which shows the goal as it is and as it becomes. goal is a goal id from <app_context> or its name; give only what changes. Returns draft_id, before, after, what is left and, with a deadline, the new monthly amount.",
    input_schema: object(
      {
        goal: { type: "string" },
        name: { type: "string" },
        target: { type: "number" },
        deadline: date,
      },
      ["goal"],
    ),
  },
  {
    name: "draft_debt_change",
    description:
      "Prepares a change to an open personal debt, for the user to confirm: a new due date or note, or settle true to mark it settled (returned outside the app, or forgiven). Money coming back is draft_debt_repayment, not this. debt is a debt id from <app_context> or the person's name; give only what changes. Returns draft_id, before and after.",
    input_schema: object(
      {
        debt: { type: "string" },
        due_date: date,
        settle: { type: "boolean" },
        note: { type: "string" },
      },
      ["debt"],
    ),
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
      "Prepares a new savings goal for the user to confirm. Nothing is saved. With account (an account id or name, not a loan) the goal follows that account's balance; without one, already_saved is what the user has put aside so far and later money is added with draft_goal_contribution. currency defaults to the account's, else the base currency. Returns draft_id, what is saved, what is left and, with a deadline, months_left and monthly: show monthly as a metric block from this result, never as a figure in the text.",
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
  {
    name: "draft_asset",
    description:
      "Prepares something the user owns for them to confirm: a flat, a house, land, a commercial property, a car or another thing. Nothing is saved. value is what it is worth now (kept as a valuation of today); purchase_price and purchase_date are what they paid and when, if they know. Give at least one of value and purchase_price. share_percent is their share when they own it with someone (100 by default); loan_account is a loan account id from <app_context> it was bought with. currency defaults to the base currency. Assets are Tenra Pro: without it the tool says so.",
    input_schema: object(
      {
        name: { type: "string", description: "What it is, short, in the user's language" },
        kind: { type: "string", enum: ["apartment", "house", "land", "commercial", "vehicle", "other"] },
        currency: { type: "string" },
        value: { type: "number", description: "What it is worth now" },
        purchase_price: { type: "number" },
        purchase_date: { ...date, description: "YYYY-MM-DD; only a year or a month given: its first day (in 2015 is 2015-01-01)" },
        share_percent: { type: "number", description: "1 to 100" },
        loan_account: { type: "string" },
      },
      ["name", "kind"],
    ),
  },
  {
    name: "draft_asset_valuation",
    description:
      "Prepares what an asset is worth now (or on a past date), in its currency, for the user to confirm. Nothing is saved. asset is an asset id from <app_context>. Give value, or area and price_per_unit (for example the square metres and the price of one in listings the user found): the phone multiplies them. note says where the figure comes from. Returns the new value, the previous one and the change.",
    input_schema: object(
      {
        asset: { type: "string" },
        value: { type: "number" },
        area: { type: "number", description: "Square metres, or another unit the price is for" },
        price_per_unit: { type: "number" },
        date,
        note: { type: "string", description: "Where the figure comes from, in the user's language" },
      },
      ["asset"],
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
    "Shows your reply. Call exactly once, last, every turn. Blocks render top to bottom as native app cards; figures come from tool results by reference, never from text. Every text, label and suggestion is in the language of the user's latest message, even though these instructions and the tool results are in English.",
  input_schema: strictObject({
    blocks: {
      type: "array",
      items: {
        anyOf: [
          block("text", {
            text: {
              type: "string",
              description:
                "Markdown in the language of the user's latest message: short sentences, **bold** for the key point (never a number), \"- \" bullets or \"1. \" steps, an optional \"### \" heading. No digits for money, not even a figure copied from a tool result: the cards beside the text show it, so refer to them in words (\"the daily allowance below\"). Only an amount the user wrote may come back.",
            },
          }),
          block("metric", { label: { type: "string" }, source, path, trend_path: nullable({ type: "string" }) }),
          block("chart", { kind: { type: "string", enum: ["bar", "line", "donut"] }, title: { type: "string" }, source, path }),
          block("transactions", { title: nullable({ type: "string" }), source }),
          block("budgets", {
            source: { ...source, description: "result_id of get_budgets: shows each budget with its limit, spent and left; use it instead of listing budgets in text" },
            category_ids: nullable({ type: "array", items: { type: "string" } }),
          }),
          block("recurring", {
            source: { ...source, description: "result_id of list_recurring: shows the subscriptions and payments with amounts and next dates, not their total (for what they cost a month add a metric at subscriptions_monthly_total_base); use it instead of listing them in text" },
          }),
          block("forecast", { source }),
          block("insight", { source, insight_id: { type: "string" } }),
          block("confirm", {
            draft_id: { type: "string", description: "A draft_id a draft tool returned to you; never a draft from <draft_status>, whose card is already in the chat" },
          }),
          block("open", {
            destination: {
              type: "string",
              enum: [
                "category", "account", "analytics", "history", "budgets", "subscriptions", "assets", "asset",
                "accounts", "deposits", "loans", "goals", "goal", "debts", "debt", "settings", "backups", "wallet_guide", "loan_payment", "review", "app_review", "manage_subscription", "create",
              ],
              description: "The first eight always work. The rest only when <app_context> has a screens line that lists them.",
            },
            target_id: nullable({ type: "string" }),
            label: { type: "string" },
            kind: nullable({ type: "string", enum: ["account", "deposit", "loan", "category"], description: "Only with destination create: what the form is for" }),
            prefill: nullable(
              object({
                name: nullable({ type: "string" }),
                amount: nullable({ type: "number", description: "As the user said it: an account's balance, a deposit's or a loan's amount, a new category's budget" }),
                currency: nullable({ type: "string", description: "ISO code" }),
                bank: nullable({ type: "string" }),
                rate_percent: nullable({ type: "number", description: "Yearly rate of a deposit or a loan" }),
                term_months: nullable({ type: "integer", description: "A loan's term" }),
                day: nullable({ type: "integer", description: "Day of the month: a deposit's interest, a loan's payment" }),
                income: nullable({ type: "boolean", description: "A category of income, not of expenses" }),
              }),
            ),
          }),
        ],
      },
    },
    mood: { type: "string", enum: ["idle", "happy", "concerned", "celebrate", "proud", "surprised", "love", "playful", "empty"] },
    suggestions: { type: "array", items: { type: "string" } },
  }),
};

export const TOOLS: Tool[] = [...readTools, ...draftTools, renderReply];
/** Every tool name a history may hold, estimate_asset_value included while it is off. */
export const TOOL_NAMES: ReadonlySet<string> = new Set(TOOLS.map((t) => t.name));

/** The tools of a turn: estimate_asset_value only while POST /v1/valuation is on, and for a
 * caller without Pro only while free valuations exist (none since 2026-11-03: Pro only). */
export function toolsFor(config: Pick<Config, "valuationEnabled" | "freeMonthlyValuations">, tier: Tier = "pro"): Tool[] {
  const valuates = config.valuationEnabled && (tier === "pro" || config.freeMonthlyValuations > 0);
  return valuates ? TOOLS : TOOLS.filter((t) => t.name !== ESTIMATE_ASSET_VALUE);
}
export const DRAFT_TOOLS: ReadonlySet<string> = new Set(draftTools.map((t) => t.name));
