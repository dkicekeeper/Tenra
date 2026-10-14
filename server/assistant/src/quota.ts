import type { Config } from "./config";

// Soft quotas in Workers KV. KV is eventually consistent, so two calls from different
// locations in the same second can both pass the last slot: acceptable for a monthly
// budget. The global daily counter is the hard stop on spend; the Anthropic Console
// spend limit sits behind it.

export type Tier = "pro" | "free";

export interface QuotaStatus {
  allowed: boolean;
  used: number;
  limit: number;
  reason?: "user" | "global";
}

// The subset of KVNamespace used here (its overloaded `get` defeats Pick<>).
export interface KVLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

const month = (now: Date) => now.toISOString().slice(0, 7);
const day = (now: Date) => now.toISOString().slice(0, 10);

async function read(kv: KVLike, key: string): Promise<number> {
  const value = await kv.get(key);
  const parsed = Number.parseInt(value ?? "0", 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function consumeCall(kv: KVLike, userId: string, tier: Tier, config: Config, now = new Date()): Promise<QuotaStatus> {
  const limit = tier === "pro" ? config.proMonthlyCalls : config.freeMonthlyCalls;
  const userKey = `calls:${userId}:${month(now)}`;
  const globalKey = `calls:all:${day(now)}`;
  const [used, global] = await Promise.all([read(kv, userKey), read(kv, globalKey)]);

  if (global >= config.globalDailyCalls) return { allowed: false, used, limit, reason: "global" };
  if (used >= limit) return { allowed: false, used, limit, reason: "user" };

  await Promise.all([
    kv.put(userKey, String(used + 1), { expirationTtl: 40 * 24 * 3600 }),
    kv.put(globalKey, String(global + 1), { expirationTtl: 2 * 24 * 3600 }),
  ]);
  return { allowed: true, used: used + 1, limit };
}
