import type { KVLike } from "./quota";
import { ValidationError } from "./validate";

// POST /v1/feedback — what a person wrote to Ten about the app itself, for the owner to read.
// The one place where this server keeps words: the person writes them to be read, and the
// app says so before sending. No model is called, so it answers where turns are refused
// (Russia, Belarus) and while the assistant is switched off.
//
// A message is kept in KV under `feedback:<time>:<id>` for a year, without the customer's id,
// and, when TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are set, sent to the owner's chat too.

export const FEEDBACK_LIMITS = {
  bodyBytes: 16 * 1024,
  textChars: 2000,
  /** Messages a day from one install (one App Attest key). */
  perDay: 5,
  keepSeconds: 365 * 86_400,
} as const;

export type Mood = "good" | "bad";

/** Where in the app the message was written. */
const SOURCES = new Set(["notice", "survey", "settings", "chat"]);

export interface FeedbackRequest {
  text: string;
  mood?: Mood;
  source?: string;
  /** Sent again after Ten tried to help with it: whether the person says it helped. */
  resolved?: boolean;
  /** The app's version, the system's, and the app's language, as short plain strings. */
  app?: string;
  os?: string;
  locale?: string;
  /** The RevenueCat app user id, only to tell Pro from free; never stored. */
  user?: string;
}

export interface FeedbackRecord {
  at: string;
  text: string;
  mood?: Mood;
  source?: string;
  resolved?: boolean;
  app?: string;
  os?: string;
  locale?: string;
  country?: string;
  tier?: "pro" | "free";
}

const short = (value: unknown, pattern: RegExp): string | undefined =>
  typeof value === "string" && pattern.test(value) ? value : undefined;

export function parseFeedbackRequest(raw: string): FeedbackRequest {
  if (raw.length > FEEDBACK_LIMITS.bodyBytes) throw new ValidationError("size");
  let input: unknown;
  try {
    input = JSON.parse(raw);
  } catch {
    throw new ValidationError("json");
  }
  if (typeof input !== "object" || input === null || Array.isArray(input)) throw new ValidationError("json");
  const body = input as Record<string, unknown>;
  if (body.protocol !== 1) throw new ValidationError("protocol");
  if (typeof body.text !== "string") throw new ValidationError("text");
  const text = body.text.trim();
  if (text.length === 0 || text.length > FEEDBACK_LIMITS.textChars) throw new ValidationError("text");
  if (body.user !== undefined && typeof body.user !== "string") throw new ValidationError("user");
  return {
    text,
    mood: body.mood === "good" || body.mood === "bad" ? body.mood : undefined,
    source: typeof body.source === "string" && SOURCES.has(body.source) ? body.source : undefined,
    resolved: typeof body.resolved === "boolean" ? body.resolved : undefined,
    app: short(body.app, /^[0-9][0-9A-Za-z.() ]{0,23}$/),
    os: short(body.os, /^[0-9][0-9.]{0,11}$/),
    locale: short(body.locale, /^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8}){0,2}$/),
    user: body.user as string | undefined,
  };
}

const day = (now: Date) => now.toISOString().slice(0, 10);

/** Counts a message against the install's day; false once the day is full. */
export async function allowFeedback(kv: KVLike, keyId: string, now = new Date()): Promise<boolean> {
  const key = `feedback-count:${day(now)}:${keyId}`;
  const used = Number.parseInt((await kv.get(key)) ?? "0", 10) || 0;
  if (used >= FEEDBACK_LIMITS.perDay) return false;
  await kv.put(key, String(used + 1), { expirationTtl: 2 * 86_400 });
  return true;
}

export async function storeFeedback(kv: KVLike, record: FeedbackRecord): Promise<string> {
  const id = crypto.randomUUID().slice(0, 8);
  const key = `feedback:${record.at}:${id}`;
  await kv.put(key, JSON.stringify(record), { expirationTtl: FEEDBACK_LIMITS.keepSeconds });
  return key;
}

/** The message as the owner reads it in Telegram: the words first, then where they came from. */
export function telegramText(record: FeedbackRecord): string {
  // A follow-up carries the same words again, with whether Ten's help settled it.
  const mood =
    record.resolved === true ? "✅ Ten helped:" : record.resolved === false ? "❌ Ten did not help:" : record.mood === "good" ? "👍" : record.mood === "bad" ? "👎" : "💬";
  const facts = [
    record.app && `Tenra ${record.app}`,
    record.os && `iOS ${record.os}`,
    record.locale,
    record.country,
    record.tier,
    record.source,
  ].filter(Boolean);
  return `${mood} ${record.text}\n\n${facts.join(" · ")}`;
}

/** Sends the message to the owner's chat. A failure is reported by status only, never by text. */
export async function notifyOwner(token: string, chatId: string, record: FeedbackRecord, send: typeof fetch = fetch): Promise<boolean> {
  try {
    const response = await send(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text: telegramText(record), disable_web_page_preview: true }),
    });
    if (!response.ok) console.log(`feedback telegram ${response.status}`);
    return response.ok;
  } catch {
    console.log("feedback telegram unreachable");
    return false;
  }
}
