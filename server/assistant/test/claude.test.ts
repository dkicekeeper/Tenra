import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import { buildParams, donePayload, errorPayload, normalizeForEcho } from "../src/claude";
import { readConfig } from "../src/config";
import { SYSTEM_PROMPT } from "../src/prompt";
import { RENDER_REPLY, TOOLS } from "../src/tools";
import { userTurn } from "./helpers";

type Block = Anthropic.Beta.BetaContentBlock;

describe("buildParams", () => {
  it("opts into the server-side fallback only where the model supports it", () => {
    const opus = buildParams(readConfig({ ASSISTANT_MODEL: "claude-opus-5-5" }), [userTurn("hi")]);
    expect(opus.fallbacks).toBe("default");
    expect(opus.betas).toEqual(["thinking-binding-controls-2026-08-01", "server-side-fallback-2026-07-01"]);
    const haiku = buildParams(readConfig({ ASSISTANT_MODEL: "claude-haiku-5-5" }), [userTurn("hi")]);
    expect(haiku.fallbacks).toBeUndefined();
    expect(haiku.betas).toEqual(["thinking-binding-controls-2026-08-01"]);
  });

  it("drops thinking blocks a deploy or a trimmed thread made stale instead of failing the turn", () => {
    const params = buildParams(readConfig({}), [userTurn("hi")]);
    expect(params.thinking).toEqual({ type: "adaptive", block_binding: { prefix_mismatch_behavior: "drop_block" } });
    expect(params.betas).toContain("thinking-binding-controls-2026-08-01");
  });

  it("keeps the cached prefix stable", () => {
    const a = buildParams(readConfig({}), [userTurn("one")]);
    const b = buildParams(readConfig({}), [userTurn("two")]);
    expect(JSON.stringify(a.tools)).toBe(JSON.stringify(b.tools));
    expect(JSON.stringify(a.system)).toBe(JSON.stringify(b.system));
    expect(a.cache_control).toEqual({ type: "ephemeral" });
    expect(a.tool_choice).toEqual({ type: "auto" });
    expect(a.output_config).toEqual({ effort: "low" });
  });

  it("has no per-request values in the system prompt", () => {
    expect(SYSTEM_PROMPT).not.toMatch(/\d{4}-\d{2}-\d{2}/);
    expect(SYSTEM_PROMPT).not.toContain("—");
    expect(SYSTEM_PROMPT).toContain(RENDER_REPLY);
  });

  it("ends the tool list with render_reply", () => {
    expect(TOOLS.at(-1)?.name).toBe(RENDER_REPLY);
  });
});

describe("normalizeForEcho", () => {
  const text = (t: string): Block => ({ type: "text", text: t, citations: null }) as Block;
  const thinking: Block = { type: "thinking", thinking: "", signature: "s" } as Block;
  const toolUse: Block = { type: "tool_use", id: "toolu_1", name: "get_accounts", input: {} } as Block;
  const fallback = { type: "fallback", from: { model: "claude-opus-5-5" }, to: { model: "claude-opus-4-8" } } as unknown as Block;

  it("leaves ordinary turns untouched", () => {
    const content = [thinking, text("a"), toolUse];
    expect(normalizeForEcho(content)).toBe(content);
  });

  it("drops the declined model's thinking and tool calls before the last fallback", () => {
    const after = { ...toolUse, id: "toolu_2" } as Block;
    expect(normalizeForEcho([thinking, text("partial"), toolUse, fallback, text("rest"), after])).toEqual([text("partial"), text("rest"), after]);
  });
});

describe("donePayload", () => {
  const message = (stop_reason: string, content: Block[]) =>
    ({
      id: "msg_1",
      type: "message",
      role: "assistant",
      model: "claude-opus-5-5",
      content,
      stop_reason,
      usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: null, cache_creation_input_tokens: 3 },
    }) as unknown as Anthropic.Beta.BetaMessage;

  it("discards refused turns", () => {
    const done = donePayload(message("refusal", [{ type: "text", text: "partial", citations: null } as Block]));
    expect(done).toMatchObject({ refused: true, content: [] });
  });

  it("flags tool input cut off by max_tokens", () => {
    const done = donePayload(message("max_tokens", [{ type: "tool_use", id: "t", name: RENDER_REPLY, input: {} } as Block]));
    expect(done.truncated).toBe(true);
    expect(done.usage).toEqual({ input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 3 });
  });
});

describe("errorPayload", () => {
  // An error event in the middle of a stream: no HTTP status, the type from its body.
  const streamError = (type: string) =>
    new Anthropic.APIError(undefined, { type: "error", error: { type, message: "x" } }, undefined, undefined, type as never);

  it("lets the app retry an overloaded or failing upstream", () => {
    expect(errorPayload(streamError("overloaded_error"))).toEqual({ code: "upstream_busy", retryable: true });
    expect(errorPayload(streamError("api_error"))).toEqual({ code: "upstream_unavailable", retryable: true });
  });

  it("does not offer a retry that cannot help", () => {
    expect(errorPayload(streamError("billing_error"))).toEqual({ code: "upstream_unavailable", retryable: false });
    expect(errorPayload(streamError("invalid_request_error"))).toEqual({ code: "bad_request", retryable: false });
    expect(errorPayload(new Error("boom"))).toEqual({ code: "internal", retryable: false });
  });
});
