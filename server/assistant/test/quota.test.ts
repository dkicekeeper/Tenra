import { describe, expect, it } from "vitest";
import { readConfig } from "../src/config";
import { consumeCall, consumeValuation, refund } from "../src/quota";
import { MemoryKV } from "./helpers";

const now = new Date("2026-10-13T12:00:00Z");

describe("consumeCall", () => {
  it("counts Pro calls per month up to the limit", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ PRO_MONTHLY_CALLS: "2" });
    expect((await consumeCall(kv, "u1", "pro", config, now)).allowed).toBe(true);
    expect((await consumeCall(kv, "u1", "pro", config, now)).used).toBe(2);
    const third = await consumeCall(kv, "u1", "pro", config, now);
    expect(third).toMatchObject({ allowed: false, reason: "user", limit: 2 });
    // A new month starts from zero.
    expect((await consumeCall(kv, "u1", "pro", config, new Date("2026-11-01T00:00:00Z"))).allowed).toBe(true);
  });

  it("gives free users nothing by default", async () => {
    const result = await consumeCall(new MemoryKV(), "u2", "free", readConfig({}), now);
    expect(result).toMatchObject({ allowed: false, reason: "user", limit: 0 });
  });

  it("stops everyone at the global daily cap", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "1" });
    expect((await consumeCall(kv, "a", "pro", config, now)).allowed).toBe(true);
    expect(await consumeCall(kv, "b", "pro", config, now)).toMatchObject({ allowed: false, reason: "global" });
  });

  it("stops free callers at their daily share and keeps the rest of the day for Pro", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "3", FREE_DAILY_CALLS: "2", FREE_MONTHLY_CALLS: "10", PRO_MONTHLY_CALLS: "10" });
    expect((await consumeCall(kv, "key:a", "free", config, now)).allowed).toBe(true);
    expect((await consumeCall(kv, "key:b", "free", config, now)).allowed).toBe(true);
    // The free share is spent: a third free caller waits for tomorrow...
    expect(await consumeCall(kv, "key:c", "free", config, now)).toMatchObject({ allowed: false, reason: "global" });
    // ...while a Pro customer still gets the slot left under the global stop.
    expect((await consumeCall(kv, "p", "pro", config, now)).allowed).toBe(true);
    expect(await consumeCall(kv, "p", "pro", config, now)).toMatchObject({ allowed: false, reason: "global" });
    // The next day starts both counters from zero.
    expect((await consumeCall(kv, "key:c", "free", config, new Date("2026-10-14T00:00:00Z"))).allowed).toBe(true);
  });

  it("does not count Pro calls against the free share", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "10", FREE_DAILY_CALLS: "1", FREE_MONTHLY_CALLS: "10", PRO_MONTHLY_CALLS: "10" });
    for (let i = 0; i < 3; i++) expect((await consumeCall(kv, "p", "pro", config, now)).allowed).toBe(true);
    expect((await consumeCall(kv, "key:a", "free", config, now)).allowed).toBe(true);
  });

  it("caps the free share at the global stop", () => {
    expect(readConfig({ GLOBAL_DAILY_CALLS: "100", FREE_DAILY_CALLS: "500" }).freeDailyCalls).toBe(100);
    expect(readConfig({ GLOBAL_DAILY_CALLS: "100" }).freeDailyCalls).toBe(100);
  });

  it("weighs a free valuation in the free share", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "100", FREE_DAILY_CALLS: "50", FREE_MONTHLY_VALUATIONS: "5", VALUATION_CALL_WEIGHT: "40" });
    expect((await consumeValuation(kv, "key:a", "free", config, now)).allowed).toBe(true);
    expect(await consumeValuation(kv, "key:b", "free", config, now)).toMatchObject({ allowed: false, reason: "global" });
  });
});

describe("refund", () => {
  it("gives back a call's month and day counts", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "2", FREE_DAILY_CALLS: "1", FREE_MONTHLY_CALLS: "1" });
    const first = await consumeCall(kv, "key:a", "free", config, now);
    expect(first.charge).toEqual({ userKey: "calls:key:a:2026-10", dailyKeys: ["calls:all:2026-10-13", "calls:free:2026-10-13"], weight: 1 });
    expect(await consumeCall(kv, "key:a", "free", config, now)).toMatchObject({ allowed: false });

    await refund(kv, first.charge!);
    expect(kv.store.get("calls:key:a:2026-10")).toBe("0");
    expect(kv.store.get("calls:all:2026-10-13")).toBe("0");
    expect(kv.store.get("calls:free:2026-10-13")).toBe("0");
    expect((await consumeCall(kv, "key:a", "free", config, now)).allowed).toBe(true);
  });

  it("never goes below zero", async () => {
    const kv = new MemoryKV();
    await refund(kv, { userKey: "calls:p:2026-10", dailyKeys: ["calls:all:2026-10-13"], weight: 40 });
    expect(kv.store.get("calls:p:2026-10")).toBe("0");
    expect(kv.store.get("calls:all:2026-10-13")).toBe("0");
  });
});
