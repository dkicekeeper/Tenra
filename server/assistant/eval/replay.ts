// Re-grades saved valuation eval records with the code as it is now, without the API: each
// record's search (its report and results) goes through computeValuation again, so a change to
// the filters or the grouping is checked against real searches for free.
//
//   npx tsx eval/replay.ts <records dir> [<records dir> ...]
//
// A records dir is one an eval run wrote (eval/out/valuation-<timestamp>, or the workflow's
// valuation-eval artifact unpacked). Prints each case whose grade changed, then the totals.
import { globSync, readFileSync } from "node:fs";
import { computeValuation, normalizeUrl } from "../src/valuation";
import { VALUATION_CASES } from "./valuation-cases";
import { grade } from "./valuation";

const roots = process.argv.slice(2);
let before = 0, after = 0, total = 0;
for (const root of roots) {
  for (const file of globSync(`${root}/**/*.json`).sort()) {
    const name = file.split("/").pop()!.replace(/\.json$/, "");
    const id = name.replace(/-\d$/, "");
    const testCase = VALUATION_CASES.find((c) => c.id === id) ?? VALUATION_CASES.find((c) => c.id === name);
    if (!testCase) continue;
    const record = JSON.parse(readFileSync(file, "utf8"));
    // The search whose result stood: the model that answered.
    const search = (record.searches ?? []).find((s: { model: string }) => s.model === record.by) ?? record.searches?.[record.searches.length - 1];
    if (!search) continue;
    const results = new Map<string, { url: string; title: string }>();
    for (const r of search.results ?? []) {
      const key = normalizeUrl(r.url);
      if (key) results.set(key, r);
    }
    const fresh = computeValuation(testCase.asset, search.report ?? undefined, results, new Date(record.result?.searched_at ?? Date.now()));
    const old = record.grade;
    const now = grade(testCase, fresh);
    total++;
    if (old.pass) before++;
    if (now.pass) after++;
    if (old.pass !== now.pass || old.detail !== now.detail) console.log(`${root.split("/").slice(-2)[0]} ${name.padEnd(30)} ${old.pass ? "pass" : "FAIL"} ${old.detail}  ->  ${now.pass ? "pass" : "FAIL"} ${now.detail}`);
  }
}
console.log(`passed before ${before}/${total}, after ${after}/${total}`);
