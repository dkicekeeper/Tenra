// Runs the assistant eval against the Claude API with the production prompt and tools
// (src/claude.ts buildParams), executing tools over the synthetic fixture.
//
//   ANTHROPIC_API_KEY=... npm run eval -- --models claude-haiku-5-5,claude-sonnet-5-5,claude-opus-5-5 --effort low,medium --yes
//
// Without --yes it prints the cost estimate and exits. Transcripts and summary.md go to
// eval/out/<timestamp>/ (git-ignored).

import Anthropic from "@anthropic-ai/sdk";
import { mkdirSync, writeFileSync } from "node:fs";
import { buildParams, normalizeForEcho } from "../src/claude";
import { readConfig, type Effort } from "../src/config";
import { RENDER_REPLY, RENDER_REPLY_TOO_EARLY } from "../src/tools";
import { CASES, type EvalCase } from "./cases";
import { appContext } from "./fixture";
import { caseCheck, universalChecks, type CheckResult, type Reply, type RunRecord } from "./grade";
import { addUsage, cost, emptyUsage, estimate, PRICING, type Usage } from "./pricing";
import { executeTool, resetDrafts, ToolInputError } from "./simulator";

type MessageParam = Anthropic.Beta.BetaMessageParam;

function arg(name: string, fallback: string): string {
  const index = process.argv.indexOf(`--${name}`);
  return index > 0 && process.argv[index + 1] && !process.argv[index + 1]!.startsWith("--") ? process.argv[index + 1]! : fallback;
}

const models = arg("models", "claude-haiku-5-5,claude-sonnet-5-5,claude-opus-5-5").split(",");
const efforts = arg("effort", "low").split(",") as Effort[];
const caseFilter = arg("cases", "all");
const concurrency = Number(arg("concurrency", "4"));
const maxCalls = Number(arg("max-calls", "8"));
const confirmed = process.argv.includes("--yes");

const cases = caseFilter === "all" ? CASES : CASES.filter((c) => caseFilter.split(",").includes(c.id));

interface Outcome {
  model: string;
  effort: Effort;
  case: EvalCase;
  record: RunRecord;
  checks: CheckResult[];
  pass: boolean;
  usage: Usage;
  calls: number;
  ms: number;
}

async function runCase(client: Anthropic, model: string, effort: Effort, testCase: EvalCase): Promise<{ outcome: Outcome; transcript: MessageParam[] }> {
  const config = readConfig({ ASSISTANT_MODEL: model, ASSISTANT_EFFORT: effort });
  const messages: MessageParam[] = [
    {
      role: "user",
      content: [
        { type: "text", text: appContext(testCase.locale) },
        // Blocks the app sends before the question: a draft made on the phone, an attachment.
        ...(testCase.notes ?? []).map((text) => ({ type: "text" as const, text })),
        { type: "text", text: testCase.prompt },
      ],
    },
  ];
  const record: RunRecord = { calls: [] };
  const usage = emptyUsage();
  const started = Date.now();
  let calls = 0;
  resetDrafts();

  try {
    while (calls < maxCalls) {
      calls += 1;
      const message = await client.beta.messages.stream(buildParams(config, messages)).finalMessage();
      addUsage(usage, message.usage);
      if (message.stop_reason === "refusal") {
        record.error = "refusal";
        break;
      }
      messages.push({ role: "assistant", content: normalizeForEcho(message.content) as Anthropic.Beta.BetaContentBlockParam[] });
      const uses = message.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
      if (message.stop_reason === "max_tokens") {
        record.error = "truncated";
        break;
      }
      if (uses.length === 0) {
        record.error = `ended without render_reply (${message.stop_reason})`;
        break;
      }
      const results: Anthropic.Beta.BetaToolResultBlockParam[] = [];
      let rendered = false;
      // As the app does (AgentConversation.swift): render_reply next to other calls can only
      // guess their ids, so it goes back as an error and the loop goes on.
      const replyTooEarly = uses.length > 1;
      for (const use of uses) {
        const input = (use.input ?? {}) as Record<string, unknown>;
        if (use.name === RENDER_REPLY && replyTooEarly) {
          record.calls.push({ id: use.id, name: use.name, input, error: RENDER_REPLY_TOO_EARLY });
          results.push({ type: "tool_result", tool_use_id: use.id, content: RENDER_REPLY_TOO_EARLY, is_error: true });
          continue;
        }
        if (use.name === RENDER_REPLY) {
          rendered = true;
          record.reply = input as unknown as Reply;
          record.calls.push({ id: use.id, name: use.name, input });
          results.push({ type: "tool_result", tool_use_id: use.id, content: "shown" });
          continue;
        }
        try {
          // As the app does: the model never sees tool_use ids, so each result names itself.
          const ref = `r${record.calls.filter((c) => c.ref).length + 1}`;
          const raw = executeTool(use.name, input);
          const result = raw && typeof raw === "object" && !Array.isArray(raw) ? { result_id: ref, ...raw } : { result_id: ref, value: raw };
          record.calls.push({ id: use.id, ref, name: use.name, input, result });
          results.push({ type: "tool_result", tool_use_id: use.id, content: JSON.stringify(result) });
        } catch (error) {
          const detail = error instanceof ToolInputError ? error.message : String(error);
          record.calls.push({ id: use.id, name: use.name, input, error: detail });
          results.push({ type: "tool_result", tool_use_id: use.id, content: detail, is_error: true });
        }
      }
      if (rendered) break;
      messages.push({ role: "user", content: results });
    }
    if (!record.reply && !record.error) record.error = `no render_reply after ${maxCalls} calls`;
  } catch (error) {
    record.error = error instanceof Anthropic.APIError ? `api ${error.status}: ${error.message}` : String(error);
  }

  const checks = [...universalChecks(record, testCase.locale, testCase.prompt), ...testCase.checks.map((c) => caseCheck(record, c))];
  return {
    outcome: { model, effort, case: testCase, record, checks, pass: checks.every((c) => c.pass), usage, calls, ms: Date.now() - started },
    transcript: messages,
  };
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

const usd = (n: number) => `$${n.toFixed(n < 0.1 ? 4 : 2)}`;

function summarize(outcomes: Outcome[]): string {
  const lines: string[] = ["# Assistant eval", "", `Cases: ${cases.length}. Prompt and tools: production (src/).`, ""];
  lines.push("| Model | Effort | Passed | Avg calls | Avg latency | Cost per case | Cost per 60 messages | Cache read share |");
  lines.push("|---|---|---|---|---|---|---|---|");
  for (const model of models) {
    for (const effort of efforts) {
      const group = outcomes.filter((o) => o.model === model && o.effort === effort);
      if (!group.length) continue;
      const total = emptyUsage();
      group.forEach((o) => addUsage(total, o.usage));
      const spent = cost(model, total);
      const inputAll = total.input_tokens + total.cache_read_input_tokens + total.cache_creation_input_tokens;
      lines.push(
        `| ${model} | ${effort} | ${group.filter((o) => o.pass).length}/${group.length} | ${(group.reduce((n, o) => n + o.calls, 0) / group.length).toFixed(1)} | ${(group.reduce((n, o) => n + o.ms, 0) / group.length / 1000).toFixed(1)} s | ${usd(spent / group.length)} | ${usd((spent / group.length) * 60)} | ${Math.round((total.cache_read_input_tokens / Math.max(inputAll, 1)) * 100)}% |`,
      );
    }
  }
  lines.push("", "## Failures", "");
  for (const o of outcomes.filter((x) => !x.pass)) {
    const failed = o.checks.filter((c) => !c.pass).map((c) => `${c.name}${c.detail ? ` (${c.detail})` : ""}`);
    lines.push(`- **${o.model} / ${o.effort} / ${o.case.id}**: ${failed.join("; ")}`);
  }
  return lines.join("\n");
}

async function main() {
  const unknown = models.filter((m) => !PRICING[m]);
  if (unknown.length) console.warn(`No price for ${unknown.join(", ")}: cost shows NaN.`);
  const estimated = models.reduce((n, m) => n + estimate(m, cases.length) * efforts.length, 0);
  console.log(`${cases.length} cases x ${models.length} models x ${efforts.length} effort levels. Upper-bound cost estimate: ${usd(estimated)}.`);
  if (!confirmed) {
    console.log("Re-run with --yes to spend it.");
    return;
  }
  if (!process.env.ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY is not set");

  const client = new Anthropic({ maxRetries: 3 });
  const outDir = `eval/out/${new Date().toISOString().replace(/[:.]/g, "-")}`;
  const jobs = models.flatMap((model) => efforts.flatMap((effort) => cases.map((c) => () => runCase(client, model, effort, c))));
  const results = await pool(jobs, concurrency);

  for (const { outcome, transcript } of results) {
    const dir = `${outDir}/${outcome.model}-${outcome.effort}`;
    mkdirSync(dir, { recursive: true });
    writeFileSync(`${dir}/${outcome.case.id}.json`, JSON.stringify({ checks: outcome.checks, record: outcome.record, usage: outcome.usage, transcript }, null, 2));
    console.log(`${outcome.pass ? "PASS" : "FAIL"} ${outcome.model} ${outcome.effort} ${outcome.case.id}`);
  }
  const summary = summarize(results.map((r) => r.outcome));
  writeFileSync(`${outDir}/summary.md`, summary);
  console.log(`\n${summary}\n\nTranscripts: ${outDir}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
