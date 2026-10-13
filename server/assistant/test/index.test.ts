import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { body, MemoryKV, userTurn } from "./helpers";

const env = (overrides: Record<string, string> = {}) =>
  ({ QUOTA: new MemoryKV(), ANTHROPIC_API_KEY: "test", REVENUECAT_SECRET_KEY: "test", ...overrides }) as never;

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
