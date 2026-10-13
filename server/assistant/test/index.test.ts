import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { assertion, storedKey } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { body, MemoryKV, userTurn } from "./helpers";

const env = (overrides: Record<string, string> = {}, kv = new MemoryKV()) =>
  ({ QUOTA: kv, ANTHROPIC_API_KEY: "test", REVENUECAT_SECRET_KEY: "test", ...overrides }) as never;

const ctx = { waitUntil() {}, passThroughOnException() {} } as never;

const post = (headers: Record<string, string>, payload = body([userTurn("hi")])) =>
  new Request("https://assistant.example/v1/turn", { method: "POST", headers, body: payload });

describe("worker routing", () => {
  it("answers health checks", async () => {
    const response = await worker.fetch(new Request("https://assistant.example/v1/health"), env(), ctx);
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ ok: true, protocol: 1 });
  });

  it("is switched off by ASSISTANT_ENABLED", async () => {
    const response = await worker.fetch(post({ "x-tenra-user": "u" }), env({ ASSISTANT_ENABLED: "false" }), ctx);
    expect(response.status).toBe(503);
  });

  it("refuses countries the Anthropic API does not serve", async () => {
    const response = await worker.fetch(post({ "x-tenra-user": "u", "cf-ipcountry": "RU" }), env(), ctx);
    expect(response.status).toBe(451);
    const kz = await worker.fetch(post({ "cf-ipcountry": "KZ" }), env(), ctx);
    expect(kz.status).toBe(401); // passes the country gate, stops at the missing user id
  });

  it("rejects malformed turns before any upstream call", async () => {
    const response = await worker.fetch(post({ "x-tenra-user": "u" }, body([userTurn("hi")], 9)), env(), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid", reason: "protocol" });
  });
});

describe("App Attest", () => {
  it("issues a one-time challenge", async () => {
    const kv = new MemoryKV();
    const response = await worker.fetch(new Request("https://assistant.example/v1/attest/challenge"), env({}, kv), ctx);
    const { challenge } = (await response.json()) as { challenge: string };
    expect(kv.store.get(`attest-challenge:${challenge}`)).toBe("1");
  });

  it("refuses an attestation that does not chain to Apple's root", async () => {
    const kv = new MemoryKV();
    await kv.put(`attest-challenge:${fixture.challenge}`, "1");
    const request = new Request("https://assistant.example/v1/attest", {
      method: "POST",
      body: JSON.stringify({ keyId: fixture.keyId, attestation: "oA==", challenge: fixture.challenge }),
    });
    const response = await worker.fetch(request, env({}, kv), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: "attestation" });
  });

  it("asks a free user for an assertion, checks it, then counts the key", async () => {
    const kv = new MemoryKV();
    await kv.put("tier:u", "free");
    await kv.put(`attest-key:${fixture.keyId}`, await storedKey());
    const config = { APP_ID: fixture.appId, FREE_MONTHLY_CALLS: "0" };
    const payload = body([userTurn("hi")]);

    const missing = await worker.fetch(post({ "x-tenra-user": "u" }, payload), env(config, kv), ctx);
    expect(missing.status).toBe(401);
    expect(await missing.json()).toEqual({ error: "attest", reason: "missing" });

    const forged = await worker.fetch(
      post({ "x-tenra-user": "u", "x-tenra-key": fixture.keyId, "x-tenra-assertion": await assertion(new TextEncoder().encode("other"), 1) }, payload),
      env(config, kv),
      ctx,
    );
    expect(await forged.json()).toEqual({ error: "attest", reason: "signature" });

    // A valid assertion passes; the quota (0 here) is then counted on the key.
    const signed = await worker.fetch(
      post({ "x-tenra-user": "u", "x-tenra-key": fixture.keyId, "x-tenra-assertion": await assertion(new TextEncoder().encode(payload), 1) }, payload),
      env(config, kv),
      ctx,
    );
    expect(signed.status).toBe(429);
    expect(await signed.json()).toMatchObject({ error: "quota", tier: "free", limit: 0 });
    expect(JSON.parse(kv.store.get(`attest-key:${fixture.keyId}`)!).counter).toBe(1);
  });
});
