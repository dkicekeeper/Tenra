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
}

function int(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export function readConfig(env: Partial<Env>): Config {
  const effort = (env.ASSISTANT_EFFORT ?? "low") as Effort;
  return {
    enabled: env.ASSISTANT_ENABLED !== "false",
    model: env.ASSISTANT_MODEL || "claude-opus-5-5",
    effort: EFFORTS.includes(effort) ? effort : "low",
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
  };
}
