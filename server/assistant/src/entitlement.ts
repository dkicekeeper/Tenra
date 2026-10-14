import type { KVLike, Tier } from "./quota";

// Pro status comes from RevenueCat (entitlement `pro`, the same id as PremiumConfig in the
// app). Founding Users are decided on the device, so a founder needs the `pro` entitlement
// granted in the RevenueCat dashboard to use the cloud. Results are cached for 10 minutes.

export const ENTITLEMENT = "pro";
const CACHE_SECONDS = 600;

export class UpstreamError extends Error {
  constructor(
    readonly service: string,
    readonly status: number,
  ) {
    super(`${service} ${status}`);
  }
}

interface Subscriber {
  subscriber?: { entitlements?: Record<string, { expires_date?: string | null } | undefined> };
}

export function tierFromSubscriber(body: Subscriber, now = Date.now()): Tier {
  const entitlement = body.subscriber?.entitlements?.[ENTITLEMENT];
  if (!entitlement) return "free";
  const expires = entitlement.expires_date;
  // null = lifetime or a promotional grant without an end.
  if (expires === null || expires === undefined) return "pro";
  return Date.parse(expires) > now ? "pro" : "free";
}

export async function resolveTier(
  kv: KVLike,
  secretKey: string,
  userId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Tier> {
  const cacheKey = `tier:${userId}`;
  const cached = await kv.get(cacheKey);
  if (cached === "pro" || cached === "free") return cached;

  const response = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`, {
    headers: { Authorization: `Bearer ${secretKey}`, Accept: "application/json" },
  });
  if (!response.ok) throw new UpstreamError("revenuecat", response.status);
  const tier = tierFromSubscriber((await response.json()) as Subscriber);
  await kv.put(cacheKey, tier, { expirationTtl: CACHE_SECONDS });
  return tier;
}
