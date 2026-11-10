import type { Config } from "./config";

// Soft quotas in Workers KV. KV is eventually consistent, so two calls from different
// locations in the same second can both pass the last slot: acceptable for a monthly
// budget. The global daily counter is a soft stop on spend; the Anthropic Console spend
// limit is the hard one behind it. Free calls also have a daily ceiling of their own below the
// global one, so free users can never take the whole day: what is left above it is Pro's.

export type Tier = "pro" | "free";

export interface QuotaStatus {
  allowed: boolean;
  used: number;
  limit: number;
  reason?: "user" | "global";
  /** What an allowed call took, so it can be given back (`refund`). */
  charge?: Charge;
}

/** The counters one allowed call raised, and by how much. */
export interface Charge {
  /** The caller's monthly key, raised by one. */
  userKey: string;
  /** The daily keys (global, and free for a free caller), raised by `weight`. */
  dailyKeys: string[];
  weight: number;
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
  return consume(kv, `calls:${userId}:${month(now)}`, tier, limit, 1, config, now);
}

/** A valuation (POST /v1/valuation): its own monthly count, and `valuationCallWeight` calls of
 * the global daily stop, since its searches cost that many chat calls. */
export async function consumeValuation(kv: KVLike, userId: string, tier: Tier, config: Config, now = new Date()): Promise<QuotaStatus> {
  const limit = tier === "pro" ? config.proMonthlyValuations : config.freeMonthlyValuations;
  return consume(kv, `valuations:${userId}:${month(now)}`, tier, limit, config.valuationCallWeight, config, now);
}

async function consume(kv: KVLike, userKey: string, tier: Tier, limit: number, weight: number, config: Config, now: Date): Promise<QuotaStatus> {
  const globalKey = `calls:all:${day(now)}`;
  const freeKey = `calls:free:${day(now)}`;
  const isFree = tier === "free";
  const [used, global, free] = await Promise.all([read(kv, userKey), read(kv, globalKey), isFree ? read(kv, freeKey) : Promise.resolve(0)]);

  if (global + weight > config.globalDailyCalls) return { allowed: false, used, limit, reason: "global" };
  if (isFree && free + weight > config.freeDailyCalls) return { allowed: false, used, limit, reason: "global" };
  if (used >= limit) return { allowed: false, used, limit, reason: "user" };

  // KV takes one write per second per key and refuses more with an error. The daily keys are
  // shared by every call, so two calls in the same second would fail one of them: a lost count
  // is cheaper than a lost answer.
  const writes = [
    kv.put(userKey, String(used + 1), { expirationTtl: 40 * 24 * 3600 }).catch(() => undefined),
    kv.put(globalKey, String(global + weight), { expirationTtl: 2 * 24 * 3600 }).catch(() => undefined),
  ];
  if (isFree) writes.push(kv.put(freeKey, String(free + weight), { expirationTtl: 2 * 24 * 3600 }).catch(() => undefined));
  await Promise.all(writes);
  const dailyKeys = isFree ? [globalKey, freeKey] : [globalKey];
  return { allowed: true, used: used + 1, limit, charge: { userKey, dailyKeys, weight } };
}

/** Gives back what an allowed call took when the model never answered it (Anthropic down,
 * overloaded or refusing the request before any output): such a call costs nothing, so it
 * should not eat the person's allowance or the day. Never goes below zero. */
export async function refund(kv: KVLike, charge: Charge): Promise<void> {
  const lower = async (key: string, by: number, ttl: number) => {
    const value = await read(kv, key);
    await kv.put(key, String(Math.max(0, value - by)), { expirationTtl: ttl }).catch(() => undefined);
  };
  await Promise.all([
    lower(charge.userKey, 1, 40 * 24 * 3600),
    ...charge.dailyKeys.map((key) => lower(key, charge.weight, 2 * 24 * 3600)),
  ]);
}
