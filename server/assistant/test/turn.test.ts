import { beforeEach, describe, expect, it, vi } from "vitest";
import { assertion, storedKey } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { MemoryKV, userTurn } from "./helpers";

// A turn whose model call fails: the stream the fake client hands out is set per test.
const scripted = vi.hoisted(() => ({ stream: undefined as undefined | (() => unknown) }));

vi.mock("@anthropic-ai/sdk", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@anthropic-ai/sdk")>();
  const Real = actual.default;
  // Inherits the error classes (static members), so errorPayload still recognises them.
  class FakeAnthropic extends Real {
    constructor(options: ConstructorParameters<typeof Real>[0]) {
      super(options);
      Object.defineProperty(this, "beta", { value: { messages: { stream: () => scripted.stream!() } } });
    }
  }
  return { ...actual, default: FakeAnthropic };
});

const { default: Anthropic } = await import("@anthropic-ai/sdk");
const { default: worker } = await import("../src/index");

/** A stream that yields `events`, then fails. */
const failingStream = (events: unknown[], error: Error) => ({
  async *[Symbol.asyncIterator]() {
    yield* events;
    throw error;
  },
  finalMessage: async () => {
    throw error;
  },
});

const down = () => new Anthropic.APIConnectionError({ message: "down" });

async function freeTurn(kv: MemoryKV) {
  await kv.put("tier:u", "free");
  await kv.put(`attest-key:${fixture.keyId}`, await storedKey());
  const payload = JSON.stringify({ protocol: 1, messages: [userTurn("hi")], user: "u" });
  const request = new Request("https://assistant.example/v1/turn", {
    method: "POST",
    headers: {
      "x-tenra-user": "u",
      "x-tenra-key": fixture.keyId,
      "x-tenra-assertion": await assertion(new TextEncoder().encode(payload), 1),
    },
    body: payload,
  });
  const pending: Promise<unknown>[] = [];
  const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {} } as never;
  const env = { QUOTA: kv, ANTHROPIC_API_KEY: "test", REVENUECAT_SECRET_KEY: "test", APP_ID: fixture.appId, FREE_MONTHLY_CALLS: "5" } as never;
  const response = await worker.fetch(request, env, ctx);
  const text = await response.text();
  await Promise.all(pending);
  return text;
}

const day = new Date().toISOString().slice(0, 10);
const month = day.slice(0, 7);

describe("a turn whose model call fails", () => {
  beforeEach(() => {
    scripted.stream = undefined;
  });

  it("gives the call back when the model never started answering", async () => {
    const kv = new MemoryKV();
    scripted.stream = () => failingStream([], down());
    const events = await freeTurn(kv);
    expect(events).toContain("event: error");
    expect(events).toContain('"code":"upstream_unavailable"');
    expect(kv.store.get(`calls:key:${fixture.keyId}:${month}`)).toBe("0");
    expect(kv.store.get(`calls:all:${day}`)).toBe("0");
    expect(kv.store.get(`calls:free:${day}`)).toBe("0");
  });

  it("keeps the count when the model failed in the middle of its answer", async () => {
    const kv = new MemoryKV();
    const started = { type: "message_start", message: {} };
    scripted.stream = () => failingStream([started], down());
    const events = await freeTurn(kv);
    expect(events).toContain("event: error");
    expect(kv.store.get(`calls:key:${fixture.keyId}:${month}`)).toBe("1");
    expect(kv.store.get(`calls:all:${day}`)).toBe("1");
  });
});
