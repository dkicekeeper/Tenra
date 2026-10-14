// Grades one assistant turn. Universal checks run on every case; each case adds its own.
// Every check is mechanical: the numbers the user sees must resolve from tool results.

import { ACCOUNTS, CATEGORIES } from "./fixture";

export interface ToolCall {
  id: string;
  name: string;
  input: Record<string, unknown>;
  result?: unknown;
  error?: string;
}

export interface Block {
  type: string;
  [key: string]: unknown;
}

export interface Reply {
  blocks: Block[];
  mood: string;
  suggestions: string[];
}

export interface RunRecord {
  calls: ToolCall[];
  reply?: Reply;
  error?: string;
}

type Input = Record<string, unknown>;

export type Check =
  | { kind: "called"; anyOf: string[] }
  | { kind: "notCalled"; tools: string[] }
  | { kind: "metric"; expected: number; tolerance?: number; label: string }
  | { kind: "metricFrom"; tool: string; pathEnds: string; args?: (input: Input) => boolean; label: string }
  | { kind: "block"; type: string }
  | { kind: "blockWith"; type: string; match: (block: Block) => boolean; label: string }
  | { kind: "toolArgs"; tool: string; match: (input: Input) => boolean; label: string };

export interface CheckResult {
  name: string;
  pass: boolean;
  detail?: string;
}

export function resolvePath(value: unknown, path: string): unknown {
  return path.split(".").filter(Boolean).reduce<unknown>((node, key) => {
    if (node === null || node === undefined) return undefined;
    if (Array.isArray(node)) return node[Number(key)];
    if (typeof node === "object") return (node as Record<string, unknown>)[key];
    return undefined;
  }, value);
}

const dataCalls = (record: RunRecord) => record.calls.filter((c) => c.name !== "render_reply");

function resolveBlock(record: RunRecord, block: Block): { call?: ToolCall; value?: unknown } {
  const call = dataCalls(record).find((c) => c.id === block.source);
  if (!call) return {};
  return { call, value: typeof block.path === "string" ? resolvePath(call.result, block.path) : call.result };
}

const near = (a: number, b: number, tolerance = 0.005) => Math.abs(a - b) <= Math.max(1, Math.abs(b) * tolerance);

const MONEY_IN_TEXT = /\d[\d\s  .,]*\s?(₸|тг(?!\p{L})|тенге|\$|€|₽|руб|usd|kzt|eur|rub|dollars?|долл)/iu;
const BIG_NUMBER = /\d[\d\s  ]{3,}\d|\d{4,}/;
// JS \b is ASCII-only even with /u: Cyrillic words are bounded with \p{L} lookarounds.
const SAVED_CLAIM = /(?<!\p{L})(сохранил[аи]?|записал[аи]?|добавил[аи]?|создал[аи]?|сохранено|записано)(?!\p{L})|\b(i('ve| have) (saved|recorded|added|logged)|saved|recorded)\b/iu;

function textOf(record: RunRecord): string {
  return (record.reply?.blocks ?? []).filter((b) => b.type === "text").map((b) => String(b.text ?? "")).join(" ");
}

// What the app's decoder needs from each block (Tenra/Services/Agent/AgentReply.swift): a
// block that misses one shows nothing on the phone. render_reply is not a strict tool, so
// this is the check that the models keep to its schema.
const STRING = (v: unknown) => typeof v === "string";
const OPTIONAL_STRING = (v: unknown) => v === undefined || v === null || typeof v === "string";
const OPTIONAL_STRINGS = (v: unknown) => v === undefined || v === null || (Array.isArray(v) && v.every(STRING));
const oneOf = (values: string[]) => (v: unknown) => typeof v === "string" && values.includes(v);
const BLOCK_FIELDS: Record<string, Record<string, (v: unknown) => boolean>> = {
  text: { text: STRING },
  metric: { label: STRING, source: STRING, path: STRING, trend_path: OPTIONAL_STRING },
  chart: { kind: oneOf(["bar", "line", "donut"]), title: STRING, source: STRING, path: STRING },
  transactions: { title: OPTIONAL_STRING, source: STRING },
  budgets: { source: STRING, category_ids: OPTIONAL_STRINGS },
  recurring: { source: STRING },
  forecast: { source: STRING },
  insight: { source: STRING, insight_id: STRING },
  confirm: { draft_id: STRING },
  open: {
    destination: oneOf(["category", "account", "analytics", "history", "budgets", "subscriptions"]),
    target_id: OPTIONAL_STRING,
    label: STRING,
  },
};

export function blockProblems(block: unknown): string[] {
  if (!block || typeof block !== "object" || Array.isArray(block)) return ["not an object"];
  const node = block as Record<string, unknown>;
  const fields = typeof node.type === "string" ? BLOCK_FIELDS[node.type] : undefined;
  if (!fields) return [`unknown type ${String(node.type)}`];
  return Object.entries(fields)
    .filter(([key, valid]) => !valid(node[key]))
    .map(([key]) => `${node.type}.${key} = ${JSON.stringify(node[key]) ?? "missing"}`);
}

export function universalChecks(record: RunRecord, locale: "ru" | "en"): CheckResult[] {
  const results: CheckResult[] = [];
  const blocks: unknown = record.reply?.blocks;
  results.push({ name: "rendered", pass: Array.isArray(blocks) && blocks.length > 0, detail: record.error });
  const malformed = (Array.isArray(blocks) ? blocks : []).flatMap(blockProblems);
  results.push({ name: "blocks_decode", pass: malformed.length === 0, detail: malformed.join("; ") || undefined });

  const broken: string[] = [];
  for (const block of record.reply?.blocks ?? []) {
    if (typeof block.source === "string") {
      const { call, value } = resolveBlock(record, block);
      if (!call) broken.push(`${block.type}: unknown source ${block.source}`);
      else if (value === undefined) broken.push(`${block.type}: path ${String(block.path)} missing in ${call.name}`);
      else if (block.type === "metric" && typeof value !== "number") broken.push(`metric: ${String(block.path)} is not a number`);
      if (block.type === "insight" && call) {
        const insights = (call.result as { insights?: { id: string }[] })?.insights ?? [];
        if (!insights.some((i) => i.id === block.insight_id)) broken.push(`insight: unknown id ${String(block.insight_id)}`);
      }
    }
    if (block.type === "confirm") {
      const drafts = dataCalls(record).map((c) => (c.result as { draft_id?: string } | undefined)?.draft_id);
      if (!drafts.includes(String(block.draft_id))) broken.push(`confirm: unknown draft ${String(block.draft_id)}`);
    }
    if (block.type === "open") {
      // The app opens nothing for an id it does not know.
      const id = block.target_id;
      const known = block.destination === "account" ? ACCOUNTS.map((a) => a.id) : CATEGORIES.map((c) => c.id);
      const needsId = block.destination === "account" || block.destination === "category";
      if (needsId && typeof id !== "string") broken.push(`open: ${String(block.destination)} without target_id`);
      else if (typeof id === "string" && (needsId || block.destination === "history") && !known.includes(id)) broken.push(`open: unknown ${String(block.destination)} ${id}`);
    }
  }
  results.push({ name: "refs_resolve", pass: broken.length === 0, detail: broken.join("; ") || undefined });

  const text = textOf(record);
  const money = text.match(MONEY_IN_TEXT)?.[0] ?? text.match(BIG_NUMBER)?.[0];
  results.push({ name: "no_money_in_text", pass: !money, detail: money });

  const letters = text.replace(/[^\p{L}]/gu, "");
  const cyrillic = letters.replace(/[^Ѐ-ӿ]/g, "").length;
  const share = letters.length ? cyrillic / letters.length : locale === "ru" ? 1 : 0;
  results.push({ name: "language", pass: locale === "ru" ? share >= 0.5 : share < 0.5, detail: `cyrillic ${Math.round(share * 100)}%` });

  const claim = text.match(SAVED_CLAIM)?.[0];
  results.push({ name: "no_saved_claim", pass: !claim, detail: claim });
  return results;
}

export function caseCheck(record: RunRecord, check: Check): CheckResult {
  const calls = dataCalls(record);
  const blocks = record.reply?.blocks ?? [];
  switch (check.kind) {
    case "called": {
      const pass = calls.some((c) => check.anyOf.includes(c.name));
      return { name: `called ${check.anyOf.join("|")}`, pass, detail: pass ? undefined : calls.map((c) => c.name).join(",") || "none" };
    }
    case "notCalled": {
      const hit = calls.find((c) => check.tools.includes(c.name));
      return { name: `not called ${check.tools.join("|")}`, pass: !hit, detail: hit?.name };
    }
    case "metric": {
      const values = blocks
        .filter((b) => b.type === "metric")
        .map((b) => resolveBlock(record, b).value)
        .filter((v): v is number => typeof v === "number");
      const pass = values.some((v) => near(v, check.expected, check.tolerance));
      return { name: check.label, pass, detail: pass ? undefined : `expected ${check.expected}, metrics ${values.join(",") || "none"}` };
    }
    case "metricFrom": {
      const pass = blocks.some((b) => {
        if (b.type !== "metric" && b.type !== "forecast") return false;
        const { call } = resolveBlock(record, b);
        const pathOk = b.type === "forecast" || String(b.path ?? "").endsWith(check.pathEnds);
        return !!call && call.name === check.tool && pathOk && (!check.args || check.args(call.input));
      });
      return { name: check.label, pass };
    }
    case "block": {
      const pass = blocks.some((b) => b.type === check.type);
      return { name: `block ${check.type}`, pass, detail: pass ? undefined : blocks.map((b) => b.type).join(",") };
    }
    case "blockWith": {
      const candidates = blocks.filter((b) => b.type === check.type);
      const pass = candidates.some((b) => check.match(b));
      return { name: check.label, pass, detail: pass ? undefined : JSON.stringify(candidates).slice(0, 300) || "none" };
    }
    case "toolArgs": {
      const matching = calls.filter((c) => c.name === check.tool);
      const pass = matching.some((c) => check.match(c.input));
      return { name: check.label, pass, detail: pass ? undefined : JSON.stringify(matching.map((c) => c.input)).slice(0, 300) };
    }
  }
}
