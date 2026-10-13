import { describe, expect, it } from "vitest";
import { CASES } from "../eval/cases";
import { TODAY, TRANSACTIONS } from "../eval/fixture";
import { caseCheck, universalChecks, type RunRecord } from "../eval/grade";
import { executeTool, resetDrafts, simulate } from "../eval/simulator";

// The harness itself, without the API: the fixture is sane, and the grader passes a correct
// reply and fails a wrong one.

describe("eval fixture and simulator", () => {
  it("is deterministic and stays in the past", () => {
    expect(TRANSACTIONS.length).toBeGreaterThan(150);
    expect(TRANSACTIONS.every((t) => t.date <= TODAY)).toBe(true);
    expect(new Set(TRANSACTIONS.map((t) => t.id)).size).toBe(TRANSACTIONS.length);
  });

  it("makes October cafes grow and taxis shrink, as the month review expects", () => {
    const cmp = simulate.comparePeriods({
      type: "expense",
      current: { from: "2026-10-01", to: "2026-10-28" },
      previous: { from: "2026-09-01", to: "2026-09-28" },
      group_by: "category",
    });
    const change = (id: string) => cmp.groups.find((g) => g.key === id)?.change ?? 0;
    expect(change("cat_cafe")).toBeGreaterThan(0);
    expect(change("cat_transport")).toBeLessThan(0);
  });

  it("computes the daily allowance from obligations before payday", () => {
    const f = simulate.forecastBalance({ until: "2026-11-10" });
    expect(f.days).toBe(13);
    expect(f.obligations.map((o) => o.label)).toEqual(["Аренда", "Netflix", "Связь", "Кредит Halyk"]);
    expect(f.daily_allowance).toBe(Math.floor(f.free_amount / 13));
  });

  it("every case has at least one specific check", () => {
    for (const c of CASES) expect(c.checks.length, c.id).toBeGreaterThan(0);
  });
});

describe("grader", () => {
  const cafeTotal = simulate.spendingSummary({ from: "2026-10-01", to: "2026-10-28", type: "expense", group_by: "none", category_ids: ["cat_cafe"] }).total;
  const cafeCase = CASES.find((c) => c.id === "ru-cafe-october")!;

  const record = (text: string, path = "total"): RunRecord => {
    const input = { from: "2026-10-01", to: "2026-10-28", type: "expense", group_by: "none", category_ids: ["cat_cafe"] };
    return {
      calls: [{ id: "toolu_a", name: "get_spending_summary", input, result: executeTool("get_spending_summary", input) }],
      reply: { blocks: [{ type: "text", text }, { type: "metric", label: "Кафе, октябрь", source: "toolu_a", path, trend_path: null }], mood: "idle", suggestions: [] },
    };
  };

  it("passes a correct reply", () => {
    const r = record("В октябре кафе заметно выросли.");
    expect(universalChecks(r, "ru").filter((c) => !c.pass)).toEqual([]);
    expect(cafeCase.checks.map((c) => caseCheck(r, c).pass)).toEqual([true, true]);
  });

  it("fails money in text, broken paths and the wrong language", () => {
    const money = universalChecks(record(`Вы потратили ${cafeTotal} ₸ на кафе.`), "ru");
    expect(money.find((c) => c.name === "no_money_in_text")?.pass).toBe(false);
    const broken = universalChecks(record("Кафе выросли.", "totals.sum"), "ru");
    expect(broken.find((c) => c.name === "refs_resolve")?.pass).toBe(false);
    const english = universalChecks(record("Cafes went up in October."), "ru");
    expect(english.find((c) => c.name === "language")?.pass).toBe(false);
  });

  it("catches a claim that a draft was saved", () => {
    resetDrafts();
    const input = { items: [{ type: "expense", amount: 1500, currency: null, category: "кофе", account: "acc_kaspi", to_account: null, date: null, note: "Кофе" }] };
    const r: RunRecord = {
      calls: [{ id: "toolu_d", name: "draft_transactions", input, result: executeTool("draft_transactions", input) }],
      reply: { blocks: [{ type: "text", text: "Записал кофе." }, { type: "confirm", draft_id: "draft_1" }], mood: "idle", suggestions: [] },
    };
    const results = universalChecks(r, "ru");
    expect(results.find((c) => c.name === "refs_resolve")?.pass).toBe(true);
    expect(results.find((c) => c.name === "no_saved_claim")?.pass).toBe(false);
  });
});
