import { describe, expect, it } from "vitest";
import { readConfig } from "../src/config";
import { consumeCall } from "../src/quota";
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
});
