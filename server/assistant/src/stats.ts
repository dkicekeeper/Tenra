// Counts what Ten is asked and how it goes, never the words (docs/domains/assistant.md §8 "Turn
// statistics"). The model labels each finished turn in render_reply (topic, outcome, language);
// the server adds the tools the turn called, how many model calls it took, the reply's mood, the
// plan and the app's build, and writes one data point to Workers Analytics Engine. No country:
// App Analytics has it, and the App Privacy label then needs no location (owner, 2026-11-25).
// The app's <draft_status> lines (sent with the next question) count the drafts saved or undone,
// by tool. Every value written is an enum value, a tool name, a number or a two-letter code: no
// question, answer, amount, name or user id can reach the dataset. Off unless
// ASSISTANT_TURN_STATS is "on" and the TURNS binding exists.

import type Anthropic from "@anthropic-ai/sdk";
import { OUTCOMES, RENDER_REPLY, TOPICS, type Outcome, type Topic } from "./tools";

/** What a <draft_status> line says happened to a draft. */
export type DraftStatus = "saved" | "undone" | "edited" | "phone";

type Message = Anthropic.Beta.BetaMessageParam;
type Block = { type: string; [key: string]: unknown };

const blocksOf = (message: Message): Block[] =>
  typeof message.content === "string" ? [{ type: "text", text: message.content }] : (message.content as unknown as Block[]);

const isQuestion = (message: Message) => message.role === "user" && !blocksOf(message).some((b) => b.type === "tool_result");

/** Index of the message that started the current turn: the last user message without tool results. */
function questionIndex(messages: Message[]): number {
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i];
    if (message && isQuestion(message)) return i;
  }
  return -1;
}

export interface TurnStat {
  topic: Topic | "unlabeled";
  outcome: Outcome | "unlabeled";
  /** ISO 639-1 of the user's latest message, as the model labels it; "xx" when it is not one. */
  language: string;
  /** The tools the turn called, render_reply aside, sorted, each once. */
  tools: string[];
  /** Model calls in the turn, this one included. */
  steps: number;
  mood: string;
  tier: string;
  /** The app's build from its User-Agent ("Tenra/93 CFNetwork/..."), "0" when absent. */
  build: string;
}

/**
 * The labels of a finished turn: the call that ends it with render_reply alone. null while tools
 * are left for the app to run (the turn goes on), as replyMood decides.
 */
export function turnStat(
  messages: Message[],
  final: Pick<Anthropic.Beta.BetaMessage, "content">,
  context: { mood: string; tier: string; userAgent?: string | null },
): TurnStat | null {
  const uses = final.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
  const [reply] = uses;
  if (uses.length !== 1 || reply?.name !== RENDER_REPLY) return null;
  const input = (reply.input && typeof reply.input === "object" ? reply.input : {}) as Record<string, unknown>;
  const start = questionIndex(messages);
  const tools = new Set<string>();
  let steps = 1;
  for (const message of messages.slice(start + 1)) {
    if (message.role !== "assistant") continue;
    steps += 1;
    for (const block of blocksOf(message)) {
      if (block.type === "tool_use" && typeof block.name === "string" && block.name !== RENDER_REPLY) tools.add(block.name);
    }
  }
  const language = typeof input.language === "string" && /^[a-z]{2}$/.test(input.language) ? input.language : "xx";
  return {
    topic: TOPICS.find((t) => t === input.topic) ?? "unlabeled",
    outcome: OUTCOMES.find((o) => o === input.outcome) ?? "unlabeled",
    language,
    tools: [...tools].sort(),
    steps,
    mood: context.mood,
    tier: context.tier,
    build: /^Tenra\/(\d{1,6})\b/.exec(context.userAgent ?? "")?.[1] ?? "0",
  };
}

/**
 * The drafts the app reports with a new question (<draft_status>, AssistantViewModel.draftStatus),
 * each with the tool that made it. Read only from the question that starts a turn, so a status
 * counts once; the words a draft made on the phone quotes are never read past its first words.
 */
export function draftStats(messages: Message[]): { tool: string; status: DraftStatus }[] {
  const last = messages[messages.length - 1];
  if (!last || !isQuestion(last)) return [];
  const text = blocksOf(last)
    .filter((b) => b.type === "text" && typeof b.text === "string")
    .map((b) => b.text as string)
    .join("\n");
  const section = /<draft_status>\n([\s\S]*?)\n<\/draft_status>/.exec(text)?.[1];
  if (!section) return [];
  const stats: { tool: string; status: DraftStatus }[] = [];
  for (const line of section.split("\n")) {
    const match = /^(draft_\d{1,6}): (.*)$/.exec(line);
    if (!match) continue;
    const [, id, said] = match as unknown as [string, string, string];
    const status: DraftStatus | undefined = said.startsWith("made on the phone")
      ? "phone"
      : said.startsWith("saved")
        ? "saved"
        : said.startsWith("undone")
          ? "undone"
          : said.startsWith("edited")
            ? "edited"
            : undefined;
    if (status) stats.push({ tool: draftTool(messages, id) ?? "unknown", status });
  }
  return stats;
}

/** The tool whose result returned this draft_id, found through its tool_result in the thread. */
function draftTool(messages: Message[], draftId: string): string | undefined {
  const marker = new RegExp(`"draft_id"\\s*:\\s*"${draftId}"`);
  let useId: string | undefined;
  for (const message of messages) {
    if (message.role !== "user") continue;
    for (const block of blocksOf(message)) {
      if (block.type !== "tool_result") continue;
      const content = block.content;
      const text = typeof content === "string" ? content : Array.isArray(content) ? content.map((c: { text?: string }) => c.text ?? "").join("") : "";
      if (marker.test(text) && typeof block.tool_use_id === "string") useId = block.tool_use_id;
    }
  }
  if (!useId) return undefined;
  for (const message of messages) {
    if (message.role !== "assistant") continue;
    for (const block of blocksOf(message)) {
      if (block.type === "tool_use" && block.id === useId && typeof block.name === "string") return block.name;
    }
  }
  return undefined;
}

/** Whether a turn is counted: the counts are on and the person did not turn the statistics off. */
export const turnCounted = (enabled: boolean, stats: boolean | undefined): boolean => enabled && stats !== false;

/** Writes a finished turn: one point, its topic as the index. */
export function writeTurn(dataset: AnalyticsEngineDataset | undefined, stat: TurnStat): void {
  dataset?.writeDataPoint({
    indexes: [stat.topic],
    blobs: ["turn", stat.topic, stat.outcome, stat.language, stat.tools.join(","), stat.mood, stat.tier, stat.build],
    doubles: [1, stat.steps, stat.tools.length],
  });
}

/** Writes what happened to the drafts reported with a question: one point each. */
export function writeDrafts(dataset: AnalyticsEngineDataset | undefined, drafts: { tool: string; status: DraftStatus }[]): void {
  for (const draft of drafts) {
    dataset?.writeDataPoint({ indexes: ["draft"], blobs: ["draft", draft.tool, draft.status], doubles: [1] });
  }
}
