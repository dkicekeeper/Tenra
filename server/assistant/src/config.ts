export interface Env {
  QUOTA: KVNamespace;
  ANTHROPIC_API_KEY: string;
  REVENUECAT_SECRET_KEY: string;
  ASSISTANT_ENABLED?: string;
  ASSISTANT_MODEL?: string;
  ASSISTANT_EFFORT?: string;
  ASSISTANT_MAX_TOKENS?: string;
  PRO_MONTHLY_CALLS?: string;
  FREE_MONTHLY_CALLS?: string;
  GLOBAL_DAILY_CALLS?: string;
  BLOCKED_COUNTRIES?: string;
  APP_ID?: string;
  VALUATION_ENABLED?: string;
  VALUATION_MODEL?: string;
  VALUATION_FALLBACK_MODEL?: string;
  VALUATION_EFFORT?: string;
  VALUATION_MAX_SEARCHES?: string;
  FREE_MONTHLY_VALUATIONS?: string;
  PRO_MONTHLY_VALUATIONS?: string;
  VALUATION_CALL_WEIGHT?: string;
}

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

const EFFORTS: readonly Effort[] = ["low", "medium", "high", "xhigh", "max"];

export interface Config {
  enabled: boolean;
  model: string;
  effort: Effort;
  maxTokens: number;
  proMonthlyCalls: number;
  freeMonthlyCalls: number;
  globalDailyCalls: number;
  blockedCountries: Set<string>;
  /** TEAMID.bundle-id, the app App Attest assertions must come from. */
  appId: string;
  /** POST /v1/valuation: off until the app version that calls it ships (and its privacy note). */
  valuationEnabled: boolean;
  /** Its own model: an eval (eval/valuation.ts) chooses it, apart from the chat's. */
  valuationModel: string;
  /** Asked again when the first model finds too few listings or declines; "" for none. */
  valuationFallbackModel: string;
  valuationEffort: Effort;
  /** Web searches per valuation, each about $0.01. */
  valuationMaxSearches: number;
  /** Valuations a month: per attested key without Pro, per customer with it. */
  freeMonthlyValuations: number;
  proMonthlyValuations: number;
  /** A valuation counts as this many chat calls in the global daily stop: its searches and
   * search results cost about that much more than a chat call on Haiku. */
  valuationCallWeight: number;
}

function int(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

const effortOf = (value: string | undefined): Effort => (EFFORTS.includes(value as Effort) ? (value as Effort) : "low");

export function readConfig(env: Partial<Env>): Config {
  return {
    enabled: env.ASSISTANT_ENABLED !== "false",
    model: env.ASSISTANT_MODEL || "claude-haiku-5-5",
    effort: effortOf(env.ASSISTANT_EFFORT),
    maxTokens: int(env.ASSISTANT_MAX_TOKENS, 16000),
    proMonthlyCalls: int(env.PRO_MONTHLY_CALLS, 900),
    freeMonthlyCalls: int(env.FREE_MONTHLY_CALLS, 0),
    globalDailyCalls: int(env.GLOBAL_DAILY_CALLS, 5000),
    blockedCountries: new Set(
      (env.BLOCKED_COUNTRIES ?? "RU,BY")
        .split(",")
        .map((c) => c.trim().toUpperCase())
        .filter(Boolean),
    ),
    appId: env.APP_ID || "SY2L2VMQP7.dakacom.Tenra",
    valuationEnabled: env.VALUATION_ENABLED === "true",
    valuationModel: env.VALUATION_MODEL || "claude-haiku-5-5",
    valuationFallbackModel: env.VALUATION_FALLBACK_MODEL ?? "",
    valuationEffort: effortOf(env.VALUATION_EFFORT),
    valuationMaxSearches: Math.max(1, Math.min(int(env.VALUATION_MAX_SEARCHES, 3), 10)),
    freeMonthlyValuations: int(env.FREE_MONTHLY_VALUATIONS, 0),
    proMonthlyValuations: int(env.PRO_MONTHLY_VALUATIONS, 10),
    valuationCallWeight: Math.max(1, int(env.VALUATION_CALL_WEIGHT, 40)),
  };
}
