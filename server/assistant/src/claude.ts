import Anthropic from "@anthropic-ai/sdk";
import type { Config } from "./config";
import { SYSTEM_PROMPT } from "./prompt";
import { TOOLS } from "./tools";

type Params = Anthropic.Beta.Messages.MessageCreateParamsStreaming;
type ContentBlock = Anthropic.Beta.BetaContentBlock;

// Models that accept the server-side refusal fallback in its "default" form on the Claude
// API. Claude Haiku 5.5 has no server-side fallback: a refusal is returned as is.
const SERVER_FALLBACK_MODELS = new Set(["claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5", "claude-fable-5-1"]);

export function buildParams(config: Config, messages: Anthropic.Beta.BetaMessageParam[]): Params {
  const params: Params = {
    model: config.model,
    max_tokens: config.maxTokens,
    // Stable prefix: tools, then this system text. Per-user context lives in the messages.
    system: [{ type: "text", text: SYSTEM_PROMPT }],
    tools: TOOLS,
    // Forced tool choice is a 400 on the current models: render_reply is required by the prompt.
    tool_choice: { type: "auto" },
    output_config: { effort: config.effort },
    // Caches the longest stable prefix, conversation included, across the turn's calls.
    cache_control: { type: "ephemeral" },
    messages,
    stream: true,
  };
  if (SERVER_FALLBACK_MODELS.has(config.model)) {
    params.betas = ["server-side-fallback-2026-07-01"];
    params.fallbacks = "default";
  }
  return params;
}

// After a mid-output fallback, blocks before the last `fallback` marker that belong to the
// declined model must not be sent back: thinking, redacted thinking and tool calls. Text
// stays. The marker itself is an ignored audit block and is dropped. Applied once, before
// the app stores the turn, so the stored history is already the form to echo.
const DROP_BEFORE_FALLBACK = new Set(["thinking", "redacted_thinking", "tool_use", "server_tool_use"]);

export function normalizeForEcho(content: ContentBlock[]): ContentBlock[] {
  let boundary = -1;
  content.forEach((block, index) => {
    if (block.type === "fallback") boundary = index;
  });
  if (boundary < 0) return content;
  return content.filter((block, index) => {
    if (index === boundary) return false;
    if (index < boundary && DROP_BEFORE_FALLBACK.has(block.type)) return false;
    return true;
  });
}

export interface DonePayload {
  content: ContentBlock[];
  stop_reason: string | null;
  model: string;
  refused: boolean;
  truncated: boolean;
  usage: {
    input_tokens: number;
    output_tokens: number;
    cache_read_input_tokens: number;
    cache_creation_input_tokens: number;
  };
}

export function donePayload(message: Anthropic.Beta.BetaMessage): DonePayload {
  const refused = message.stop_reason === "refusal";
  const hasToolUse = message.content.some((b) => b.type === "tool_use");
  return {
    // A refused turn is discarded by the app (a mid-stream refusal leaves a partial).
    content: refused ? [] : normalizeForEcho(message.content),
    stop_reason: message.stop_reason,
    model: message.model,
    refused,
    // A tool input cut off by max_tokens can still look valid: never run it.
    truncated: message.stop_reason === "max_tokens" && hasToolUse,
    usage: {
      input_tokens: message.usage.input_tokens,
      output_tokens: message.usage.output_tokens,
      cache_read_input_tokens: message.usage.cache_read_input_tokens ?? 0,
      cache_creation_input_tokens: message.usage.cache_creation_input_tokens ?? 0,
    },
  };
}

export interface ErrorPayload {
  code: "upstream_busy" | "upstream_unavailable" | "bad_request" | "internal";
  retryable: boolean;
}

export function errorPayload(error: unknown): ErrorPayload {
  if (error instanceof Anthropic.RateLimitError) return { code: "upstream_busy", retryable: true };
  if (error instanceof Anthropic.BadRequestError) return { code: "bad_request", retryable: false };
  if (error instanceof Anthropic.APIConnectionError) return { code: "upstream_unavailable", retryable: true };
  if (error instanceof Anthropic.APIError && (error.status ?? 0) >= 500) return { code: "upstream_unavailable", retryable: true };
  return { code: "internal", retryable: false };
}
