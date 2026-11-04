// The valuation eval (docs/plan-assets-roadmap.md §3, A6): runs POST /v1/valuation's own code
// (src/valuation.ts: the prompt, the live web search, the checks and the arithmetic) on every
// case of eval/valuation-cases.ts and compares the value with the case's reference.
//
//   ANTHROPIC_API_KEY=... npm run eval:valuation -- --models claude-haiku-5-5,claude-sonnet-5-5 --yes
//   ANTHROPIC_API_KEY=... npm run eval:valuation -- --models claude-haiku-5-5 --fallback claude-sonnet-5-5 --yes
//
// Without --yes it prints the cost estimate and exits. A case passes when the status is the
// expected one and the value is within the case's tolerance of its reference, in its currency.
// Also reported: how many listings were found and kept, links dropped as not in the search
// results (a high share is the model citing pages it did not get), searches, cost and time.
// Results go to eval/out/valuation-<timestamp>/ (git-ignored).

import Anthropic from "@anthropic-ai/sdk";
import { mkdirSync, writeFileSync } from "node:fs";
import { readConfig, type Effort } from "../src/config";
import { parseValuationRequest, valuate, valuationConfig, type Valuation, type ValuationResult } from "../src/valuation";
import { addUsage, cost, emptyUsage, PRICING, WEB_SEARCH_USD, type Usage } from "./pricing";
import { VALUATION_CASES, type ValuationCase } from "./valuation-cases";

function arg(name: string, fallback: string): string {
  const index = process.argv.indexOf(`--${name}`);
  return index > 0 && process.argv[index + 1] && !process.argv[index + 1]!.startsWith("--") ? process.argv[index + 1]! : fallback;
}

const models = arg("models", "claude-haiku-5-5,claude-sonnet-5-5").split(",");
const efforts = arg("effort", "low").split(",") as Effort[];
const caseFilter = arg("cases", "all");
const searches = arg("searches", "3");
// "none": each model alone; a model id: asked again when the first finds too few listings.
const fallback = arg("fallback", "none");
const concurrency = Number(arg("concurrency", "3"));
// Each case this many times: the search results change from one run to the next.
const repeat = Math.max(1, Math.floor(Number(arg("repeat", "1"))) || 1);
const confirmed = process.argv.includes("--yes");
const cases = caseFilter === "all" ? VALUATION_CASES : VALUATION_CASES.filter((c) => caseFilter.split(",").includes(c.id));

export interface Grade {
  pass: boolean;
  /** value ÷ reference − 1, for a case with a reference and a value in its currency. */
  deviation?: number;
  detail: string;
}

export function grade(testCase: ValuationCase, result: ValuationResult): Grade {
  const expected = testCase.expect;
  if (expected.status === "insufficient") {
    const pass = result.status === "insufficient" || result.accuracy === "low";
    return { pass, detail: pass ? result.status : `${result.status}, accuracy ${result.accuracy}` };
  }
  if (result.status !== "ok" || result.value === null) return { pass: false, detail: `${result.status} (${result.reason}), ${result.count} comparables` };
  if (result.currency !== expected.currency) return { pass: false, detail: `currency ${result.currency}, expected ${expected.currency}` };
  const deviation = result.value / expected.value - 1;
  const pass = Math.abs(deviation) <= expected.tolerance;
  return { pass, deviation, detail: `${pct(deviation)} (tolerance ±${Math.round(expected.tolerance * 100)}%)` };
}

interface Outcome {
  /** 1 to `repeat`. */
  attempt?: number;
  model: string;
  effort: Effort;
  testCase: ValuationCase;
  result?: ValuationResult;
  valuation?: Valuation;
  grade: Grade;
  usage: Usage;
  searches: number;
  usd: number;
  ms: number;
}

const pct = (x: number) => `${x >= 0 ? "+" : ""}${(x * 100).toFixed(1)}%`;
const usd = (n: number) => `$${n.toFixed(n < 0.1 ? 4 : 2)}`;
const money = (n: number | null | undefined, currency?: string | null) => (n === null || n === undefined ? "-" : `${Math.round(n).toLocaleString("en-US")} ${currency ?? ""}`.trim());

async function runCase(client: Anthropic, model: string, effort: Effort, testCase: ValuationCase): Promise<Outcome> {
  const started = Date.now();
  const usage = emptyUsage();
  // The case goes through the endpoint's own checks first.
  const { asset } = parseValuationRequest(JSON.stringify({ protocol: 1, asset: testCase.asset }));
  const config = valuationConfig(
    readConfig({ VALUATION_MODEL: model, VALUATION_EFFORT: effort, VALUATION_MAX_SEARCHES: searches, VALUATION_FALLBACK_MODEL: fallback === "none" ? "" : fallback }),
  );
  try {
    const valuation = await valuate((params) => client.beta.messages.stream(params).finalMessage(), config, asset, new Date());
    let spent = 0;
    let searched = 0;
    for (const { model: used, outcome } of valuation.searches) {
      addUsage(usage, outcome.usage);
      spent += cost(used, { ...emptyUsage(), ...outcome.usage }) + outcome.usage.searches * WEB_SEARCH_USD;
      searched += outcome.usage.searches;
    }
    const refused = valuation.searches.every((s) => s.outcome.refused);
    const graded = refused ? { pass: false, detail: "refused" } : grade(testCase, valuation.result);
    return { model, effort, testCase, result: valuation.result, valuation, grade: graded, usage, searches: searched, usd: spent, ms: Date.now() - started };
  } catch (error) {
    const detail = error instanceof Anthropic.APIError ? `api ${error.status}: ${error.message}` : String(error);
    return { model, effort, testCase, grade: { pass: false, detail }, usage, searches: 0, usd: cost(model, usage), ms: Date.now() - started };
  }
}

async function pool<T>(jobs: (() => Promise<T>)[], size: number): Promise<T[]> {
  const results: T[] = [];
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(size, jobs.length) }, async () => {
      while (next < jobs.length) {
        const index = next++;
        results[index] = await jobs[index]!();
      }
    }),
  );
  return results;
}

const median = (xs: number[]) => {
  if (!xs.length) return Number.NaN;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
};

function summarize(outcomes: Outcome[]): string {
  const lines = ["# Valuation eval", "", `Cases: ${cases.length}${repeat > 1 ? `, each ${repeat} times` : ""}. Searches per valuation: up to ${searches}. Code and prompt: production (src/valuation.ts).`, ""];
  if (fallback !== "none") lines.push(`Fallback: ${fallback}, asked again when the first model finds too few listings or declines.`, "");
  lines.push("| Model | Effort | Passed | Median abs deviation | Comparables (median) | Unverified links | Fallback used | Searches (avg) | Cost per valuation | Latency (avg) |");
  lines.push("|---|---|---|---|---|---|---|---|---|---|");
  for (const model of models) {
    for (const effort of efforts) {
      const group = outcomes.filter((o) => o.model === model && o.effort === effort);
      if (!group.length) continue;
      const deviations = group.flatMap((o) => (o.grade.deviation === undefined ? [] : [Math.abs(o.grade.deviation)]));
      const reported = group.reduce((n, o) => n + (reportedOf(o) ?? 0), 0);
      const unverified = group.reduce((n, o) => n + (o.result?.excluded.unverified_url ?? 0), 0);
      lines.push(
        `| ${model} | ${effort} | ${group.filter((o) => o.grade.pass).length}/${group.length} | ${deviations.length ? pct(median(deviations)) : "-"} | ${median(group.map((o) => o.result?.count ?? 0))} | ${unverified}/${reported} | ${group.filter((o) => o.valuation?.usedFallback).length} | ${(group.reduce((n, o) => n + o.searches, 0) / group.length).toFixed(1)} | ${usd(group.reduce((n, o) => n + o.usd, 0) / group.length)} | ${(group.reduce((n, o) => n + o.ms, 0) / group.length / 1000).toFixed(1)} s |`,
      );
    }
  }
  if (repeat > 1) {
    // How steady a case is across runs: passes of the repeats and every deviation.
    lines.push("", "## Repeats", "", "| Case | Model | Effort | Passed | Deviations |", "|---|---|---|---|---|");
    for (const model of models) {
      for (const effort of efforts) {
        for (const testCase of cases) {
          const runs = outcomes.filter((o) => o.model === model && o.effort === effort && o.testCase.id === testCase.id);
          const deviations = runs.map((o) => (o.grade.deviation === undefined ? o.grade.detail.split(" ")[0] : pct(o.grade.deviation))).join(", ");
          lines.push(`| ${testCase.id} | ${model} | ${effort} | ${runs.filter((o) => o.grade.pass).length}/${runs.length} | ${deviations} |`);
        }
      }
    }
  }
  lines.push("", "## Cases", "", "| Case | Model | Effort | Value | Reference | Result | Comparables | Accuracy | By |", "|---|---|---|---|---|---|---|---|---|");
  for (const o of outcomes) {
    const expected = o.testCase.expect;
    const reference = expected.status === "ok" ? money(expected.value, expected.currency) : "too few";
    lines.push(
      `| ${o.testCase.id} | ${o.model} | ${o.effort} | ${money(o.result?.value, o.result?.currency)} | ${reference} | ${o.grade.pass ? "pass" : "FAIL"}: ${o.grade.detail} | ${o.result?.count ?? 0} of ${reportedOf(o) ?? 0} | ${o.result?.accuracy ?? "-"} | ${o.valuation?.model ?? "-"} |`,
    );
  }
  return lines.join("\n");
}

/** Listings the search whose result stands reported. */
const reportedOf = (o: Outcome) => o.valuation?.searches.find((s) => s.model === o.valuation?.model)?.outcome.report?.listings.length;

function estimate(): number {
  // Up to the search limit per case, about 40k input tokens of results and 3k output.
  return models.reduce((total, model) => {
    const tokens = cost(model, { input_tokens: 40_000, output_tokens: 3_000, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });
    const backup =
      fallback === "none" ? 0 : cost(fallback, { input_tokens: 40_000, output_tokens: 3_000, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }) + Number(searches) * WEB_SEARCH_USD;
    // The fallback runs for about a third of the cases.
    return total + (tokens + Number(searches) * WEB_SEARCH_USD + backup / 3) * cases.length * efforts.length * repeat;
  }, 0);
}

async function main() {
  const unknown = models.filter((m) => !PRICING[m]);
  if (unknown.length) console.warn(`No price for ${unknown.join(", ")}: cost shows NaN.`);
  console.log(`${cases.length} cases x ${repeat} x ${models.length} models x ${efforts.length} effort levels. Cost estimate: ${usd(estimate())}.`);
  if (!confirmed) {
    console.log("Re-run with --yes to spend it.");
    return;
  }
  if (!process.env.ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY is not set");

  const client = new Anthropic({ maxRetries: 3 });
  const outDir = `eval/out/valuation-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  const jobs = models.flatMap((model) =>
    efforts.flatMap((effort) =>
      cases.flatMap((c) => Array.from({ length: repeat }, (_, i) => () => runCase(client, model, effort, c).then((o) => ({ ...o, attempt: i + 1 })))),
    ),
  );
  const outcomes = await pool(jobs, concurrency);

  for (const o of outcomes) {
    const dir = `${outDir}/${o.model}-${o.effort}`;
    mkdirSync(dir, { recursive: true });
    const record = {
      grade: o.grade,
      result: o.result,
      by: o.valuation?.model,
      searches: o.valuation?.searches.map(({ model, outcome }) => ({
        model,
        queries: outcome.queries,
        trace: outcome.trace,
        report: outcome.report,
        results: [...outcome.results.values()],
        usage: outcome.usage,
      })),
      usd: o.usd,
    };
    writeFileSync(`${dir}/${o.testCase.id}${repeat > 1 ? `-${o.attempt}` : ""}.json`, JSON.stringify(record, null, 2));
    console.log(`${o.grade.pass ? "PASS" : "FAIL"} ${o.model} ${o.effort} ${o.testCase.id}: ${o.grade.detail}`);
  }
  const summary = summarize(outcomes);
  writeFileSync(`${outDir}/summary.md`, summary);
  console.log(`\n${summary}\n\nRecords: ${outDir}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
