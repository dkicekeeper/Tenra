import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { EVENT_LIMITS, parseEventsBatch, writeEvents } from "../src/events";
import { turnCounted } from "../src/stats";
import { parseTurnRequest, ValidationError } from "../src/validate";
import { body, MemoryKV, userTurn } from "./helpers";

/** A dataset that records what it is given. */
class RecordingDataset {
  points: { indexes?: string[]; blobs?: string[]; doubles?: number[] }[] = [];
  writeDataPoint(point: { indexes?: string[]; blobs?: string[]; doubles?: number[] }) {
    this.points.push(point);
  }
}

const event = (fields: Record<string, unknown> = {}) => ({
  kind: "m",
  name: "onboarding",
  value: "currency",
  cohort: "2026-W49",
  day: 0,
  plan: "free",
  entries: "0",
  reminder: false,
  capture: false,
  onboarding: "none",
  furthest0: "welcome",
  build: "101",
  ios: "26",
  lang: "ru",
  ...fields,
});

const env = (overrides: Record<string, unknown> = {}) =>
  ({ QUOTA: new MemoryKV(), ANTHROPIC_API_KEY: "test", REVENUECAT_SECRET_KEY: "test", APP_EVENTS: "on", ...overrides }) as never;

const ctx = { waitUntil() {}, passThroughOnException() {} } as never;

const post = (payload: unknown, headers: Record<string, string> = {}) =>
  new Request("https://assistant.example/v1/events", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.7", ...headers },
    body: typeof payload === "string" ? payload : JSON.stringify(payload),
  });

const code = (raw: unknown) => {
  try {
    parseEventsBatch(raw);
    return "ok";
  } catch (error) {
    return error instanceof ValidationError ? error.code : String(error);
  }
};

describe("events batch", () => {
  it("accepts a valid batch and writes one point per event", async () => {
    const dataset = new RecordingDataset();
    const response = await worker.fetch(
      post({ events: [event(), event({ kind: "c", name: "open", value: "cold", day: 3, reminder: true, capture: true })] }),
      env({ EVENTS: dataset }),
      ctx,
    );
    expect(response.status).toBe(204);
    expect(dataset.points).toHaveLength(2);
    expect(dataset.points[0]).toEqual({
      indexes: ["onboarding"],
      blobs: ["m", "onboarding", "currency", "2026-W49", "free", "0", "off", "off", "none", "welcome", "ru", "101", "26"],
      doubles: [1, 0],
    });
    expect(dataset.points[1]?.blobs?.slice(0, 3)).toEqual(["c", "open", "cold"]);
    expect(dataset.points[1]?.blobs?.slice(6, 8)).toEqual(["on", "on"]);
    expect(dataset.points[1]?.doubles).toEqual([1, 3]);
  });

  it("knows every milestone and counter the app sends", () => {
    const valid: [string, string, string][] = [
      ["m", "installed", ""],
      ["m", "onboarding_done", "skipped"],
      ["m", "first_screen", "wardrobe"],
      ["m", "entries", "50"],
      ["m", "notifications", "denied"],
      ["m", "paywall_first", "asset_estimate"],
      ["m", "returned", "week2"],
      ["m", "path", "currency"],
      ["m", "path", "reminder"],
      ["m", "renewal_off", ""],
      ["c", "paywall", "purchased:loan_add:annual"],
      ["c", "paywall", "closed:onboarding:none"],
      ["c", "feature", "statement"],
      ["c", "ten", "notice_hidden"],
      ["c", "moment", "budget"],
    ];
    for (const [kind, name, value] of valid) expect(code({ events: [event({ kind, name, value })] }), `${name}:${value}`).toBe("ok");
  });

  it("refuses an unknown name, value or field", () => {
    expect(code({ events: [event({ name: "salary" })] })).toBe("events");
    expect(code({ events: [event({ value: "password" })] })).toBe("events");
    expect(code({ events: [event({ kind: "x" })] })).toBe("events");
    expect(code({ events: [event({ kind: "c", name: "installed", value: "" })] })).toBe("events");
    expect(code({ events: [event({ amount: 1500 })] })).toBe("events");
    expect(code({ events: [event({ plan: "vip" })] })).toBe("events");
    expect(code({ events: [event({ reminder: "yes" })] })).toBe("events");
    expect(code({ events: [event({ day: -1 })] })).toBe("events");
    expect(code({ events: [event({ day: 401 })] })).toBe("events");
    expect(code({ events: [event({ day: 1.5 })] })).toBe("events");
    expect(code({ events: [event({ value: "purchased:loan_add:forever" }), event()].map((e) => ({ ...e, name: "paywall", kind: "c" })) })).toBe("events");
    expect(code({ notEvents: [] })).toBe("events");
    expect(code([event()])).toBe("events");
  });

  it("refuses a value that is not on its list even if it looks harmless", () => {
    expect(code({ events: [event({ entries: "37" })] })).toBe("events");
    expect(code({ events: [event({ lang: "russian" })] })).toBe("events");
    expect(code({ events: [event({ cohort: "2026-48" })] })).toBe("events");
    expect(code({ events: [event({ build: "1.10" })] })).toBe("events");
    expect(code({ events: [event({ ios: "26.1" })] })).toBe("events");
    expect(code({ events: [event({ kind: "m", name: "entries", value: "37" })] })).toBe("events");
    expect(code({ events: [event({ kind: "m", name: "path", value: "none" })] })).toBe("events");
    expect(code({ events: [event({ lang: "pt-BR" })] })).toBe("ok");
  });

  it("refuses more than 100 events or a body over 64 KB", async () => {
    expect(code({ events: Array.from({ length: EVENT_LIMITS.batch + 1 }, () => event()) })).toBe("events");
    expect(code({ events: [] })).toBe("events");
    const dataset = new RecordingDataset();
    const huge = JSON.stringify({ events: [event()], pad: "x".repeat(EVENT_LIMITS.bodyBytes) });
    const response = await worker.fetch(post(huge), env({ EVENTS: dataset }), ctx);
    expect(response.status).toBe(400);
    expect(dataset.points).toHaveLength(0);
  });

  it("answers 400 and writes nothing for a broken batch", async () => {
    const dataset = new RecordingDataset();
    const response = await worker.fetch(post({ events: [event(), event({ name: "salary" })] }), env({ EVENTS: dataset }), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "events" });
    expect(dataset.points).toHaveLength(0);
    expect((await worker.fetch(post("not json"), env({ EVENTS: dataset }), ctx)).status).toBe(400);
  });

  it("answers 204 and writes nothing with APP_EVENTS off", async () => {
    const dataset = new RecordingDataset();
    const response = await worker.fetch(post({ events: [event()] }), env({ EVENTS: dataset, APP_EVENTS: "off" }), ctx);
    expect(response.status).toBe(204);
    expect(dataset.points).toHaveLength(0);
  });

  it("answers 429 when the rate limit says no, and keys it by the address only", async () => {
    const dataset = new RecordingDataset();
    const keys: string[] = [];
    const limiter = { limit: async ({ key }: { key: string }) => (keys.push(key), { success: false }) };
    const response = await worker.fetch(post({ events: [event()] }), env({ EVENTS: dataset, EVENTS_LIMIT: limiter }), ctx);
    expect(response.status).toBe(429);
    expect(keys).toEqual(["203.0.113.7"]);
    expect(dataset.points).toHaveLength(0);
  });

  it("is POST only", async () => {
    const response = await worker.fetch(new Request("https://assistant.example/v1/events"), env(), ctx);
    expect(response.status).toBe(405);
  });

  it("writes nothing without a dataset", () => {
    expect(() => writeEvents(undefined, [parseEventsBatch({ events: [event()] })[0]!])).not.toThrow();
  });
});

describe("the turn's stats flag", () => {
  const turn = (extra: Record<string, unknown>) => JSON.stringify({ ...JSON.parse(body([userTurn("Привет")])), ...extra });

  it("is read from the turn and must be a boolean", () => {
    expect(parseTurnRequest(turn({ stats: false })).stats).toBe(false);
    expect(parseTurnRequest(turn({})).stats).toBeUndefined();
    expect(() => parseTurnRequest(turn({ stats: "no" }))).toThrow(ValidationError);
  });

  it("stops the turn's and the drafts' counts when false", () => {
    expect(turnCounted(true, undefined)).toBe(true);
    expect(turnCounted(true, true)).toBe(true);
    expect(turnCounted(true, false)).toBe(false);
    expect(turnCounted(false, undefined)).toBe(false);
  });
});
