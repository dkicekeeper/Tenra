import type Anthropic from "@anthropic-ai/sdk";
import { TOOL_NAMES } from "./tools";

// The app sends the whole conversation (Anthropic message format) on every call and
// appends the server's `done.content` verbatim, so history is append-only. This module
// checks the shape and limits; it never rewrites history.

export const PROTOCOL_VERSION = 1;

export const LIMITS = {
  bodyBytes: 256 * 1024,
  messages: 80,
  // The app's <app_context> block (accounts, categories with their ids, up to 30 facts, goals,
  // debts) is one text block; a heavy user's passes 4 000 characters. The body limit above
  // bounds the cost either way.
  userTextChars: 16 * 1024,
  // forecast_balance's daily series for a year with its obligations passes 32 KB.
  toolResultChars: 64 * 1024,
} as const;

export interface TurnRequest {
  protocol: number;
  messages: Anthropic.Beta.BetaMessageParam[];
  /** The RevenueCat app user id inside the signed body (apps from 1.6 on); the header alone is
   *  only a claim anyone could copy. */
  user?: string;
}

export class ValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v);

const USER_BLOCKS = new Set(["text", "tool_result"]);
const ASSISTANT_BLOCKS = new Set(["text", "thinking", "redacted_thinking", "tool_use"]);

function checkUserBlock(block: Json): void {
  if (block.type === "text") {
    if (typeof block.text !== "string" || block.text.length > LIMITS.userTextChars) throw new ValidationError("user_text");
    return;
  }
  // tool_result
  if (typeof block.tool_use_id !== "string") throw new ValidationError("tool_result_id");
  const content = block.content;
  const size =
    typeof content === "string"
      ? content.length
      : Array.isArray(content)
        ? content.reduce((n: number, part: unknown) => {
            if (!isObject(part) || part.type !== "text" || typeof part.text !== "string") throw new ValidationError("tool_result_content");
            return n + part.text.length;
          }, 0)
        : -1;
  if (size < 0 || size > LIMITS.toolResultChars) throw new ValidationError("tool_result_content");
}

function checkAssistantBlock(block: Json): void {
  if (block.type === "tool_use") {
    if (typeof block.id !== "string" || typeof block.name !== "string" || !TOOL_NAMES.has(block.name)) {
      throw new ValidationError("tool_use");
    }
    if (!isObject(block.input)) throw new ValidationError("tool_use_input");
  }
}

export function parseTurnRequest(raw: string): TurnRequest {
  if (raw.length > LIMITS.bodyBytes) throw new ValidationError("too_large");
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new ValidationError("json");
  }
  if (!isObject(body)) throw new ValidationError("body");
  if (body.protocol !== PROTOCOL_VERSION) throw new ValidationError("protocol");
  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > LIMITS.messages) {
    throw new ValidationError("messages");
  }

  messages.forEach((message: unknown, index) => {
    if (!isObject(message)) throw new ValidationError("message");
    // role "system" carries operator authority in the Messages API; only the server sets it.
    if (message.role !== "user" && message.role !== "assistant") throw new ValidationError("role");
    if (index === 0 && message.role !== "user") throw new ValidationError("first_role");
    const content = message.content;
    const blocks: unknown[] = typeof content === "string" ? [{ type: "text", text: content }] : Array.isArray(content) ? content : [];
    if (blocks.length === 0) throw new ValidationError("content");
    const allowed = message.role === "user" ? USER_BLOCKS : ASSISTANT_BLOCKS;
    for (const block of blocks) {
      if (!isObject(block) || typeof block.type !== "string" || !allowed.has(block.type)) throw new ValidationError("block_type");
      if ("cache_control" in block) throw new ValidationError("cache_control");
      if (message.role === "user") checkUserBlock(block);
      else checkAssistantBlock(block);
    }
  });

  const last = messages[messages.length - 1] as Json;
  if (last.role !== "user") throw new ValidationError("last_role");

  const user = body.user;
  if (user !== undefined && (typeof user !== "string" || !isValidUserId(user))) throw new ValidationError("user");

  return { protocol: PROTOCOL_VERSION, messages: messages as Anthropic.Beta.BetaMessageParam[], user };
}

// RevenueCat app user ids: `$RCAnonymousID:<hex>` or an id the app sets.
const USER_ID = /^[A-Za-z0-9$:._-]{1,128}$/;

export function isValidUserId(id: string | null): id is string {
  return id !== null && USER_ID.test(id);
}
