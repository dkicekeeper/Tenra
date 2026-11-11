import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { allowFeedback, FEEDBACK_LIMITS, notifyOwner, parseFeedbackRequest, telegramText } from "../src/feedback";
import { ValidationError } from "../src/validate";
import { assertion, storedKey } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { MemoryKV } from "./helpers";

const env = (overrides: Record<string, string> = {}, kv = new MemoryKV()) =>
  ({ QUOTA: kv, ANTHROPIC_API_KEY: "test", REVENUECAT_SECRET_KEY: "test", APP_ID: fixture.appId, ...overrides }) as never;

const waited: Promise<unknown>[] = [];
const ctx = { waitUntil: (p: Promise<unknown>) => waited.push(p), passThroughOnException() {} } as never;

const payload = (fields: Record<string, unknown> = {}) => JSON.stringify({ protocol: 1, text: "The loan screen is confusing", ...fields });

/** A feedback request signed by the registered fixture key. */
async function signed(kv: MemoryKV, raw = payload(), headers: Record<string, string> = {}, counter = 1) {
  if (!kv.store.has(`attest-key:${fixture.keyId}`)) await kv.put(`attest-key:${fixture.keyId}`, await storedKey());
  const bytes = new TextEncoder().encode(raw);
  return new Request("https://assistant.example/v1/feedback", {
    method: "POST",
    headers: { "x-tenra-key": fixture.keyId, "x-tenra-assertion": await assertion(bytes, counter), ...headers },
    body: bytes,
  });
}

const stored = (kv: MemoryKV) => [...kv.store.entries()].filter(([key]) => key.startsWith("feedback:")).map(([, value]) => JSON.parse(value));

describe("feedback request", () => {
  it("keeps the words and the short facts, and drops what it does not know", () => {
    const parsed = parseFeedbackRequest(payload({ text: "  Нравится  ", mood: "good", source: "notice", app: "1.8.3 (77)", os: "27.0", locale: "ru-KZ", extra: 1 }));
    expect(parsed).toEqual({ text: "Нравится", mood: "good", source: "notice", app: "1.8.3 (77)", os: "27.0", locale: "ru-KZ", user: undefined });
    const odd = parseFeedbackRequest(payload({ mood: "meh", source: "elsewhere", app: "<script>", os: "x", locale: "!!" }));
    expect(odd).toMatchObject({ mood: undefined, source: undefined, app: undefined, os: undefined, locale: undefined });
  });

  it("refuses an empty, an oversized or a malformed message", () => {
    const code = (raw: string) => {
      try {
        parseFeedbackRequest(raw);
      } catch (error) {
        return (error as ValidationError).code;
      }
    };
    expect(code(payload({ text: "   " }))).toBe("text");
    expect(code(payload({ text: "x".repeat(FEEDBACK_LIMITS.textChars + 1) }))).toBe("text");
    expect(code(payload({ protocol: 2 }))).toBe("protocol");
    expect(code("not json")).toBe("json");
    expect(code(JSON.stringify({ protocol: 1, text: "x".repeat(FEEDBACK_LIMITS.bodyBytes) }))).toBe("size");
  });

  it("counts an install's messages by the day", async () => {
    const kv = new MemoryKV();
    const today = new Date("2026-11-11T10:00:00Z");
    for (let i = 0; i < FEEDBACK_LIMITS.perDay; i++) expect(await allowFeedback(kv, "k", today)).toBe(true);
    expect(await allowFeedback(kv, "k", today)).toBe(false);
    expect(await allowFeedback(kv, "other", today)).toBe(true);
    expect(await allowFeedback(kv, "k", new Date("2026-11-12T00:00:01Z"))).toBe(true);
  });
});

describe("POST /v1/feedback", () => {
  it("stores a signed message without the customer's id", async () => {
    const kv = new MemoryKV();
    const request = await signed(kv, payload({ mood: "bad", source: "survey", app: "1.8.3", os: "27.0", locale: "ru" }), { "cf-ipcountry": "KZ" });
    const response = await worker.fetch(request, env({}, kv), ctx);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    const [record] = stored(kv);
    expect(record).toMatchObject({ text: "The loan screen is confusing", mood: "bad", source: "survey", app: "1.8.3", os: "27.0", locale: "ru", country: "KZ" });
    expect(Object.keys(record)).not.toContain("user");
    expect(JSON.stringify(record)).not.toContain(fixture.keyId);
  });

  it("refuses a message that is not from the app", async () => {
    const kv = new MemoryKV();
    const request = new Request("https://assistant.example/v1/feedback", { method: "POST", body: payload() });
    const response = await worker.fetch(request, env({}, kv), ctx);
    expect(response.status).toBe(401);
    expect(stored(kv)).toHaveLength(0);
  });

  it("answers where turns are refused and while the assistant is off", async () => {
    const kv = new MemoryKV();
    const response = await worker.fetch(await signed(kv, payload(), { "cf-ipcountry": "RU" }), env({ ASSISTANT_ENABLED: "false" }, kv), ctx);
    expect(response.status).toBe(200);
    expect(stored(kv)[0]).toMatchObject({ country: "RU" });
    const challenge = await worker.fetch(new Request("https://assistant.example/v1/attest/challenge", { headers: { "cf-ipcountry": "RU" } }), env({ ASSISTANT_ENABLED: "false" }, kv), ctx);
    expect(challenge.status).toBe(200);
  });

  it("stops an install after its day's messages", async () => {
    const kv = new MemoryKV();
    for (let i = 1; i <= FEEDBACK_LIMITS.perDay; i++) {
      expect((await worker.fetch(await signed(kv, payload(), {}, i), env({}, kv), ctx)).status).toBe(200);
    }
    const over = await worker.fetch(await signed(kv, payload(), {}, FEEDBACK_LIMITS.perDay + 1), env({}, kv), ctx);
    expect(over.status).toBe(429);
    expect(stored(kv)).toHaveLength(FEEDBACK_LIMITS.perDay);
  });

  it("rejects a malformed message before checking the signature", async () => {
    const kv = new MemoryKV();
    const response = await worker.fetch(await signed(kv, payload({ text: "" })), env({}, kv), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid", reason: "text" });
  });
});

describe("the owner's Telegram chat", () => {
  const record = { at: "2026-11-11T10:00:00.000Z", text: "Нет виджета баланса", mood: "bad" as const, app: "1.8.3", os: "27.0", locale: "ru", country: "KZ", tier: "free" as const, source: "notice" };

  it("puts the words first, then where they came from", () => {
    expect(telegramText(record)).toBe("👎 Нет виджета баланса\n\nTenra 1.8.3 · iOS 27.0 · ru · KZ · free · notice");
    expect(telegramText({ at: record.at, text: "Hi" })).toBe("💬 Hi\n\n");
  });

  it("sends the message to the chat, and survives Telegram being down", async () => {
    const calls: { url: string; body: unknown }[] = [];
    const ok = (async (url: string, init: RequestInit) => {
      calls.push({ url, body: JSON.parse(init.body as string) });
      return new Response("{}", { status: 200 });
    }) as unknown as typeof fetch;
    expect(await notifyOwner("TOKEN", "42", record, ok)).toBe(true);
    expect(calls[0]!.url).toBe("https://api.telegram.org/botTOKEN/sendMessage");
    expect(calls[0]!.body).toMatchObject({ chat_id: "42", text: telegramText(record) });
    const down = (async () => {
      throw new Error("network");
    }) as unknown as typeof fetch;
    expect(await notifyOwner("TOKEN", "42", record, down)).toBe(false);
  });
});
