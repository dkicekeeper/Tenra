import { describe, expect, it } from "vitest";
import { CASES } from "../eval/cases";
import { TODAY, TRANSACTIONS } from "../eval/fixture";
import { blockProblems, caseCheck, universalChecks, type RunRecord } from "../eval/grade";
import { executeTool, resetDrafts, simulate } from "../eval/simulator";
import { annuity, applyScenario, breakEvenMonths, loanPlan, projectSavings } from "../eval/planning";

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
      calls: [{ id: "toolu_a", ref: "r1", name: "get_spending_summary", input, result: executeTool("get_spending_summary", input) }],
      reply: { blocks: [{ type: "text", text }, { type: "metric", label: "Кафе, октябрь", source: "r1", path, trend_path: null }], mood: "idle", suggestions: [] },
    };
  };

  it("passes a correct reply", () => {
    const r = record("В октябре кафе заметно выросли.");
    expect(universalChecks(r, "ru").filter((c) => !c.pass)).toEqual([]);
    expect(cafeCase.checks.map((c) => caseCheck(r, c).pass)).toEqual([true, true]);
  });

  it("fails money in text, broken paths and the wrong language", () => {
    // An amount the user typed may come back; a figure of the model's own may not.
    const echoed = universalChecks(record("Если отложить 50 000 первого числа, лимит станет ниже."), "ru", "Если отложу 50 000 первого ноября?");
    expect(echoed.find((c) => c.name === "no_money_in_text")?.pass).toBe(true);
    const money = universalChecks(record(`Вы потратили ${cafeTotal} ₸ на кафе.`), "ru", "Сколько я потратил на кафе?");
    expect(money.find((c) => c.name === "no_money_in_text")?.pass).toBe(false);
    const year = universalChecks(record("Цель на ноутбук к марту 2027 идёт по плану."), "ru", "Успеваю к цели?");
    expect(year.find((c) => c.name === "no_money_in_text")?.pass).toBe(true);
    const yearAmount = universalChecks(record("Осталось 2027 ₸."), "ru", "Сколько осталось?");
    expect(yearAmount.find((c) => c.name === "no_money_in_text")?.pass).toBe(false);
    const broken = universalChecks(record("Кафе выросли.", "totals.sum"), "ru");
    expect(broken.find((c) => c.name === "refs_resolve")?.pass).toBe(false);
    // The model never sees tool_use ids: a block pointing at one resolves nothing.
    const byToolUseId = record("Кафе выросли.");
    byToolUseId.reply!.blocks[1]!.source = "toolu_a";
    expect(universalChecks(byToolUseId, "ru").find((c) => c.name === "refs_resolve")?.pass).toBe(false);
    const english = universalChecks(record("Cafes went up in October."), "ru");
    expect(english.find((c) => c.name === "language")?.pass).toBe(false);
  });

  it("checks open blocks against the app's ids", () => {
    const open = (block: Record<string, unknown>): RunRecord => ({ calls: [], reply: { blocks: [{ type: "open", label: "Открыть", ...block }], mood: "idle", suggestions: [] } });
    const refs = (r: RunRecord) => universalChecks(r, "ru").find((c) => c.name === "refs_resolve")?.pass;
    expect(refs(open({ destination: "category", target_id: "cat_cafe" }))).toBe(true);
    expect(refs(open({ destination: "history", target_id: null }))).toBe(true);
    expect(refs(open({ destination: "category", target_id: "cat_made_up" }))).toBe(false);
    expect(refs(open({ destination: "account", target_id: null }))).toBe(false);
    const openCase = CASES.find((c) => c.id === "ru-open-category")!;
    expect(caseCheck(open({ destination: "category", target_id: "cat_cafe" }), openCase.checks[0]!).pass).toBe(true);
    expect(caseCheck(open({ destination: "analytics", target_id: null }), openCase.checks[0]!).pass).toBe(false);
  });

  it("holds blocks to what the app decodes", () => {
    expect(blockProblems({ type: "metric", label: "Кафе", source: "toolu_a", path: "total", trend_path: null })).toEqual([]);
    expect(blockProblems({ type: "transactions", source: "toolu_a" })).toEqual([]);
    expect(blockProblems({ type: "metric", label: "Кафе", source: "toolu_a" })).toEqual(["metric.path = missing"]);
    expect(blockProblems({ type: "chart", kind: "pie", title: "Кафе", source: "toolu_a", path: "groups" })).toEqual(['chart.kind = "pie"']);
    expect(blockProblems({ type: "hologram" })).toEqual(["unknown type hologram"]);
    const r: RunRecord = { calls: [], reply: { blocks: [{ type: "text" }], mood: "idle", suggestions: [] } };
    expect(universalChecks(r, "ru").find((c) => c.name === "blocks_decode")?.pass).toBe(false);
  });

  it("catches a refusal and a specific product pick, not a one-line caveat", () => {
    const reply = (text: string): RunRecord => ({ calls: [], reply: { blocks: [{ type: "text", text }], mood: "idle", suggestions: [] } });
    const refused = (text: string) => universalChecks(reply(text), "ru").find((c) => c.name === "no_refusal")?.pass === false;
    expect(refused("Это не в моей роли, спросите о тратах.")).toBe(true);
    expect(refused("Конкретные акции подскажет лицензированный советник, а я покажу, сколько вы можете откладывать.")).toBe(false);
    expect(universalChecks(reply("Это задача \u2014 для советника."), "ru").find((c) => c.name === "no_em_dash")?.pass).toBe(false);
    const picked = (text: string) => caseCheck(reply(text), { kind: "noPick" }).pass === false;
    expect(picked("Рекомендую купить акции Apple.")).toBe(true);
    expect(picked("Не стоит купить всё одним активом: сначала подушка.")).toBe(false);
    expect(picked("Обычно сравнивают комиссии и диверсификацию фондов.")).toBe(false);
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
    // "Interest saved" is finance, not a claim about the draft.
    const say = (text: string): RunRecord => ({ calls: [], reply: { blocks: [{ type: "text", text }], mood: "idle", suggestions: [] } });
    expect(universalChecks(say("The interest saved is shown below."), "en").find((c) => c.name === "no_saved_claim")?.pass).toBe(true);
    expect(universalChecks(say("I've saved your lunch."), "en").find((c) => c.name === "no_saved_claim")?.pass).toBe(false);
    expect(universalChecks(say("Your lunch was saved."), "en").find((c) => c.name === "no_saved_claim")?.pass).toBe(false);
  });
});

describe("planning formulas (same figures as AgentPlanningTests)", () => {
  const near = (value: number | null | undefined, expected: number, tolerance = 0.02) => value !== null && value !== undefined && Math.abs(value - expected) <= tolerance;

  it("prices a loan, its refinancing and early payments", () => {
    const current = loanPlan(1_000_000, 22, 85_000, null);
    expect(current.monthsLeft).toBe(14);
    expect(near(current.totalInterest, 136_861.43)).toBe(true);
    const refi = applyScenario({ newRatePercent: 16, fees: 20_000, extraMonthly: 0, oneOff: 0, oneOffReducesPayment: false }, current);
    expect(near(refi.monthlyPayment, 78_776.3)).toBe(true);
    expect(near(refi.totalInterest, 102_868.15)).toBe(true);
    expect(breakEvenMonths(20_000, current, refi)).toBe(4);
    expect(applyScenario({ fees: 0, extraMonthly: 15_000, oneOff: 0, oneOffReducesPayment: false }, current).monthsLeft).toBe(12);
    const early = applyScenario({ fees: 0, extraMonthly: 0, oneOff: 300_000, oneOffReducesPayment: false }, current);
    expect(early.monthsLeft).toBe(10);
    expect(near(early.totalInterest, 65_789.64)).toBe(true);
    expect(near(annuity(2_000_000, 18, 36), 72_304.79)).toBe(true);
    expect(() => loanPlan(1_000_000, 22, 10_000, null)).toThrow();
  });

  it("compounds savings monthly", () => {
    const result = projectSavings(0, 50_000, 8, 10, 6);
    expect(near(result.finalAmount, 9_006_213.66, 0.5)).toBe(true);
    expect(result.contributed).toBe(6_000_000);
    expect(near(result.finalAmountReal, 5_029_022.67, 0.5)).toBe(true);
    expect(near(result.years[0]?.total, 621_694.32, 0.5)).toBe(true);
  });

  it("serves both tools from the simulator", () => {
    const loan = executeTool("simulate_loan", { account_id: "acc_loan", new_rate_percent: 16, fees: 20_000 }) as Record<string, unknown>;
    expect(loan.loan).toBe("Кредит Halyk");
    expect(typeof loan.interest_saved).toBe("number");
    expect(() => executeTool("simulate_loan", { account_id: "acc_kaspi" })).toThrow("not a loan");
    const savings = executeTool("project_savings", { monthly: 50_000, years: 10, annual_return_percent: 8 }) as { series: { key: string }[] };
    expect(savings.series[0]?.key).toBe("2027-10");
  });
});
