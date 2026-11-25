// POST /v1/events: how far new people get in the app and whether they come back, as counts
// (docs/plan-sales.md §4). The app sends milestones (each once per install) and counters, never an
// identifier of the install, the person or the device, never an amount, a text or a name. Every
// value must be on its list below, or the whole batch is refused; the app's enums
// (Tenra/Services/Analytics/UsageEvents.swift) are the same lists and change with them in one
// commit. One Analytics Engine point per event, in the dataset tenra_app_events (wrangler.toml).

import { ValidationError } from "./validate";

export const EVENT_LIMITS = { batch: 100, bodyBytes: 64 * 1024, maxDay: 400 } as const;

export interface UsageEventWire {
  kind: "m" | "c";
  name: string;
  value: string;
  cohort: string;
  day: number;
  plan: string;
  entries: string;
  reminder: boolean;
  capture: boolean;
  onboarding: string;
  furthest0: string;
  build: string;
  ios: string;
  lang: string;
}

/** The paywall's gates, PaywallSource's raw values in the app. */
const GATES = [
  "account_add", "deposit_add", "loan_add", "debt_add", "asset_add", "asset_estimate", "voice", "import",
  "assistant", "assistant_attachment", "insights", "settings", "onboarding",
] as const;
const SCREENS = ["home", "history", "analytics", "finances", "assistant", "add", "import", "settings", "paywall", "wardrobe"];
const PAYWALL_STEPS = ["shown", "closed", "purchase_started", "purchased", "cancelled", "failed", "restored"];
const PAYWALL_PLANS = ["monthly", "annual", "lifetime", "none"];

/** Milestones (kind "m"): name → its values. "" for one without a value. */
const MILESTONES: Record<string, readonly string[]> = {
  installed: [""],
  onboarding: ["welcome", "currency", "account", "categories", "capture"],
  onboarding_done: ["finished", "skipped", "restored"],
  first_screen: SCREENS,
  entries: ["1", "5", "10", "50"],
  reminder_on: [""],
  notifications: ["granted", "denied"],
  capture_first: [""],
  widget_on: [""],
  ten_opened: [""],
  paywall_first: GATES,
  trial_started: [""],
  renewal_off: [""],
  converted: [""],
  returned: ["1", "2", "3", "7", "14", "30", "week2"],
};

/** Counters (kind "c"): name → its values. The paywall's is `step:gate:plan`. */
const COUNTERS: Record<string, readonly string[]> = {
  open: ["cold", "warm"],
  entry: [""],
  paywall: PAYWALL_STEPS.flatMap((step) => GATES.flatMap((gate) => PAYWALL_PLANS.map((plan) => `${step}:${gate}:${plan}`))),
  feature: ["budget", "goal", "debt", "loan", "deposit", "asset", "csv_export", "year_review", "voice", "statement"],
  ten: ["asked", "notice_opened", "notice_hidden"],
  moment: ["goal", "debt", "loan", "asset", "budget", "capture"],
};

/** Every name with its values, for the app's tests and the docs. */
export const ALLOWED: Record<string, readonly string[]> = { ...MILESTONES, ...COUNTERS };

const FIELDS = {
  plan: ["free", "trial", "pro", "founder"],
  entries: ["0", "1", "2-4", "5-9", "10-49", "50+"],
  onboarding: ["none", "finished", "skipped", "restored"],
  furthest0: ["none", "welcome", "currency", "account", "categories", "capture", "onboarding_done", "entry", "reminder"],
} as const;

const KEYS = ["kind", "name", "value", "cohort", "day", "plan", "entries", "reminder", "capture", "onboarding", "furthest0", "build", "ios", "lang"];
const COHORT = /^\d{4}-W\d{2}$/;
const BUILD = /^\d{1,6}$/;
const IOS = /^\d{2}$/;
const LANG = /^[a-z]{2}(-[A-Z]{2})?$/;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const oneOf = (list: readonly string[], value: unknown) => typeof value === "string" && list.includes(value);

function checkEvent(raw: unknown): UsageEventWire {
  if (!isObject(raw)) throw new ValidationError("events");
  const keys = Object.keys(raw);
  if (keys.length !== KEYS.length || !KEYS.every((key) => key in raw)) throw new ValidationError("events");
  const { kind, name, value, cohort, day, plan, entries, reminder, capture, onboarding, furthest0, build, ios, lang } = raw;
  const lists = kind === "m" ? MILESTONES : kind === "c" ? COUNTERS : undefined;
  if (!lists || typeof name !== "string" || !Object.hasOwn(lists, name) || !oneOf(lists[name]!, value)) throw new ValidationError("events");
  if (typeof cohort !== "string" || !COHORT.test(cohort)) throw new ValidationError("events");
  if (typeof day !== "number" || !Number.isInteger(day) || day < 0 || day > EVENT_LIMITS.maxDay) throw new ValidationError("events");
  if (!oneOf(FIELDS.plan, plan) || !oneOf(FIELDS.entries, entries) || !oneOf(FIELDS.onboarding, onboarding) || !oneOf(FIELDS.furthest0, furthest0)) {
    throw new ValidationError("events");
  }
  if (typeof reminder !== "boolean" || typeof capture !== "boolean") throw new ValidationError("events");
  if (typeof build !== "string" || !BUILD.test(build) || typeof ios !== "string" || !IOS.test(ios) || typeof lang !== "string" || !LANG.test(lang)) {
    throw new ValidationError("events");
  }
  return raw as unknown as UsageEventWire;
}

/** The batch, every event checked; any unknown value refuses all of it. */
export function parseEventsBatch(body: unknown): UsageEventWire[] {
  if (!isObject(body) || !Array.isArray(body.events)) throw new ValidationError("events");
  const events = body.events;
  if (events.length === 0 || events.length > EVENT_LIMITS.batch) throw new ValidationError("events");
  return events.map(checkEvent);
}

/** One point per event; the event's name is the index. */
export function writeEvents(dataset: AnalyticsEngineDataset | undefined, events: UsageEventWire[]): void {
  for (const e of events) {
    dataset?.writeDataPoint({
      indexes: [e.name],
      blobs: [e.kind, e.name, e.value, e.cohort, e.plan, e.entries, e.reminder ? "on" : "off", e.capture ? "on" : "off", e.onboarding, e.furthest0, e.lang, e.build, e.ios],
      doubles: [1, e.day],
    });
  }
}
