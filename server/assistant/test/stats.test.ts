import { describe, expect, it } from "vitest";
import type Anthropic from "@anthropic-ai/sdk";
import { draftStats, turnStat, writeDrafts, writeTurn } from "../src/stats";

type Message = Anthropic.Beta.BetaMessageParam;

const QUESTION = "Сколько я потратил на кафе у Magnum в октябре, 45 000?";

const thread = (draftStatus?: string): Message[] => [
  { role: "user", content: [{ type: "text", text: "<app_context>\nlocale: ru\n</app_context>\nкофе 1500" }] },
  { role: "assistant", content: [{ type: "tool_use", id: "u1", name: "draft_transactions", input: { items: [] } }] },
  { role: "user", content: [{ type: "tool_result", tool_use_id: "u1", content: '{"draft_id":"draft_1","saved":false}' }] },
  { role: "assistant", content: [{ type: "tool_use", id: "u2", name: "draft_budget", input: {} }] },
  { role: "user", content: [{ type: "tool_result", tool_use_id: "u2", content: '{"draft_id":"draft_12","saved":false}' }] },
  { role: "assistant", content: [{ type: "tool_use", id: "r1", name: "render_reply", input: { blocks: [], mood: "idle", suggestions: [] } }] },
  { role: "user", content: [{ type: "text", text: `${draftStatus ? `${draftStatus}\n` : ""}${QUESTION}` }] },
  { role: "assistant", content: [{ type: "tool_use", id: "u3", name: "get_spending_summary", input: {} }, { type: "tool_use", id: "u4", name: "get_budgets", input: {} }] },
  { role: "user", content: [{ type: "tool_result", tool_use_id: "u3", content: "{}" }, { type: "tool_result", tool_use_id: "u4", content: "{}" }] },
  { role: "assistant", content: [{ type: "tool_use", id: "u5", name: "get_spending_summary", input: {} }] },
  { role: "user", content: [{ type: "tool_result", tool_use_id: "u5", content: "{}" }] },
];

const reply = (input: Record<string, unknown>): Pick<Anthropic.Beta.BetaMessage, "content"> => ({
  content: [{ type: "tool_use", id: "final", name: "render_reply", input } as Anthropic.Beta.BetaToolUseBlock],
});

const context = { mood: "concerned", tier: "free", userAgent: "Tenra/93 CFNetwork/3860.100.1 Darwin/27.0.0" };

describe("turnStat", () => {
  it("labels a finished turn with the model's topic, outcome and language and the turn's tools", () => {
    const stat = turnStat(thread(), reply({ blocks: [], mood: "concerned", suggestions: [], topic: "spending", outcome: "done", language: "ru" }), context);
    expect(stat).toEqual({
      topic: "spending",
      outcome: "done",
      language: "ru",
      tools: ["get_budgets", "get_spending_summary"],
      steps: 3,
      mood: "concerned",
      tier: "free",
      build: "93",
    });
  });

  it("counts nothing while tools are left for the app to run", () => {
    const final = { content: [{ type: "tool_use", id: "x", name: "get_budgets", input: {} } as Anthropic.Beta.BetaToolUseBlock] };
    expect(turnStat(thread(), final, context)).toBeNull();
  });

  it("keeps only enum values and codes: anything else is unlabeled", () => {
    const stat = turnStat(thread(), reply({ topic: QUESTION, outcome: "great", language: "русский" }), { mood: "idle", tier: "pro", userAgent: QUESTION });
    expect(stat?.topic).toBe("unlabeled");
    expect(stat?.outcome).toBe("unlabeled");
    expect(stat?.language).toBe("xx");
    expect(stat?.build).toBe("0");
  });
});

describe("draftStats", () => {
  it("reads the drafts reported with a question, each with the tool that made it", () => {
    const status = [
      "<draft_status>",
      "draft_1: saved",
      "draft_12: undone",
      'draft_3: made on the phone from the user\'s message "такси 2500 Magnum", not by you; saved',
      "</draft_status>",
    ].join("\n");
    const messages = thread(status).slice(0, 7);
    expect(draftStats(messages)).toEqual([
      { tool: "draft_transactions", status: "saved" },
      { tool: "draft_budget", status: "undone" },
      { tool: "unknown", status: "phone" },
    ]);
  });

  it("reads nothing on a later call of the same turn, so a status counts once", () => {
    const status = "<draft_status>\ndraft_1: saved\n</draft_status>";
    expect(draftStats(thread(status))).toEqual([]);
  });
});

describe("writing", () => {
  it("never writes the words of the conversation", () => {
    const points: AnalyticsEngineDataPoint[] = [];
    const dataset = { writeDataPoint: (point?: AnalyticsEngineDataPoint) => point && points.push(point) } as AnalyticsEngineDataset;
    const stat = turnStat(thread(), reply({ topic: "spending", outcome: "partial", language: "ru" }), context);
    expect(stat).not.toBeNull();
    if (stat) writeTurn(dataset, stat);
    const status = "<draft_status>\ndraft_3: made on the phone from the user's message \"Magnum 45 000\", not by you; saved\n</draft_status>";
    writeDrafts(dataset, draftStats(thread(status).slice(0, 7)));
    expect(points).toHaveLength(2);
    const written = JSON.stringify(points);
    for (const word of ["Magnum", "45 000", "кафе", "кофе", "октябр"]) expect(written).not.toContain(word);
    expect(points[0]?.blobs).toEqual(["turn", "spending", "partial", "ru", "get_budgets,get_spending_summary", "concerned", "free", "93"]);
    expect(points[1]?.blobs).toEqual(["draft", "unknown", "phone"]);
  });

  it("writes nothing without the dataset", () => {
    expect(() => writeDrafts(undefined, [{ tool: "draft_budget", status: "saved" }])).not.toThrow();
  });
});
