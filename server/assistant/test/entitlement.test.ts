import { describe, expect, it, vi } from "vitest";
import { resolveTier, tierFromSubscriber, UpstreamError } from "../src/entitlement";
import { MemoryKV } from "./helpers";

const now = Date.parse("2026-10-13T12:00:00Z");

describe("tierFromSubscriber", () => {
  it("reads the pro entitlement", () => {
    expect(tierFromSubscriber({ subscriber: { entitlements: { pro: { expires_date: null } } } }, now)).toBe("pro");
    expect(tierFromSubscriber({ subscriber: { entitlements: { pro: { expires_date: "2026-11-01T00:00:00Z" } } } }, now)).toBe("pro");
    expect(tierFromSubscriber({ subscriber: { entitlements: { pro: { expires_date: "2026-10-01T00:00:00Z" } } } }, now)).toBe("free");
    expect(tierFromSubscriber({ subscriber: { entitlements: {} } }, now)).toBe("free");
    expect(tierFromSubscriber({}, now)).toBe("free");
  });
});

describe("resolveTier", () => {
  it("asks RevenueCat once and caches the answer", async () => {
    const kv = new MemoryKV();
    const fetchMock = vi.fn(async () => Response.json({ subscriber: { entitlements: { pro: { expires_date: null } } } }));
    expect(await resolveTier(kv, "sk", "$RCAnonymousID:abc", fetchMock as unknown as typeof fetch)).toBe("pro");
    expect(await resolveTier(kv, "sk", "$RCAnonymousID:abc", fetchMock as unknown as typeof fetch)).toBe("pro");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.revenuecat.com/v1/subscribers/%24RCAnonymousID%3Aabc");
    expect((init.headers as Record<string, string>).Authorization).toBe("Bearer sk");
  });

  it("surfaces RevenueCat failures", async () => {
    const fetchMock = vi.fn(async () => new Response("", { status: 503 }));
    await expect(resolveTier(new MemoryKV(), "sk", "u", fetchMock as unknown as typeof fetch)).rejects.toBeInstanceOf(UpstreamError);
  });
});
