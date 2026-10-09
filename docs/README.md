# Tenra — Documentation

Every current document lives in `docs/`. Everything that is no longer current lives in
`docs/archive/`. [CLAUDE.md](../CLAUDE.md) routes Claude to the right file by what is being edited;
this file is the full index.

## Rules

1. **Current docs only, in `docs/`.** A document is current when it describes the app as it is
   now, or work still in flight: an open plan, a running spike, the findings tracker, release
   notes, the support site. Nothing documentation-like lives elsewhere in the repo, apart from the
   files tools require at fixed paths: `CLAUDE.md`, `AGENTS.md`, `.claude/skills/*/SKILL.md`.
2. **Stale goes to `docs/archive/`, in the same commit that makes it stale.** A plan that landed,
   was reverted or rejected → `docs/archive/plans/` (keep its row in
   [plans/README.md](plans/README.md)). A finished audit or report → `docs/archive/`. A spec the
   code has moved past → `docs/archive/specs/`, after its lasting rules are folded into the
   domain doc. Archived files are history: don't update them, don't route to them for current
   rules.
3. **Names: lowercase, words joined by hyphens**, for files and folders, in `docs/archive/` too:
   `promotion-plan.md`, `performance-audit-2026-07.md`, `2026-07-31-app-intents.md`. Dates are
   ISO (`2026-10-09`). Exceptions: `README.md` (a folder's index) and locale codes
   (`pt-BR.md`, as in `pt-BR.lproj`).
4. **Skills that write documents elsewhere by default** (superpowers → `docs/superpowers/`,
   GSD → `.planning/`) write plans into `docs/plans/` and specs into the matching domain doc, or
   into `docs/plans/` while the work is in flight.
5. **A new document gets a row in this index**; a new domain also gets a row in the
   [CLAUDE.md](../CLAUDE.md) "When to Read Which Doc" table.

## Layout

```
docs/
├── README.md            this index and the rules
├── *.md                 project-wide references (architecture, concurrency, design system,
│                        gotchas, insights metrics) and product docs (monetization, promotion)
├── domains/             one file per domain: its rules, indexes, traps
├── localization/        localization rules and status, one ASO/metadata file per locale
├── plans/               work in flight + the findings tracker (README.md)
├── releases/            What's New per version, as pasted into App Store Connect
├── public/              the GitHub Pages site (privacy policy, terms, support); path fixed
│                        by .github/workflows/static.yml
└── archive/             everything no longer current: reports, finished plans (plans/),
                         superseded specs (specs/), the April 2026 GSD planning (planning-2026-04/)
```

## Project-wide references

| File | Purpose |
|------|---------|
| [architecture.md](architecture.md) | MVVM + Coordinator, TransactionStore, BalanceCoordinator, Repository, CoreData v12, backups |
| [concurrency.md](concurrency.md) | Swift 6 concurrency, CoreData threading, `@Observable` rules, DataSnapshot |
| [design-system.md](design-system.md) | DesignKit in Tenra: tokens, components, padding contract, amount formatting |
| [gotchas.md](gotchas.md) | SwiftUI layout, performance hot paths, previews, ignorable console warnings |
| [insights-metrics-reference.md](insights-metrics-reference.md) | Per-metric reference for InsightsService (formulas, granularity, data sources) |

## Domains

| File | Purpose |
|------|---------|
| [domains/accounts.md](domains/accounts.md) | Account, series and parsed-date indexes, AccountDetailView read contract, ranking |
| [domains/categories.md](domains/categories.md) | Category, subcategory and budget aggregates, style cache, reorder |
| [domains/charts.md](domains/charts.md) | Insight charts (DesignKit + `PeriodChartAdapters.swift`), scrolling, sparklines |
| [domains/csv.md](domains/csv.md) | CSV import/export round-trip rules |
| [domains/currency.md](domains/currency.md) | FX rates, providers, prewarm, base-currency aggregation |
| [domains/deposits.md](domains/deposits.md) | Interest accrual, capitalization, account ↔ deposit conversion |
| [domains/import.md](domains/import.md) | Statement and receipt recognition, DocumentSnapshot seam, Apple Intelligence policy |
| [domains/insights.md](domains/insights.md) | InsightsService, DataSnapshot, PreAggregatedData, signal notifications |
| [domains/intents.md](domains/intents.md) | App Intents and Siri, App Shortcuts, the Wallet automation |
| [domains/loans.md](domains/loans.md) | Payments, linking, amortization |
| [domains/logos.md](domains/logos.md) | Logo provider chain, ServiceLogoRegistry |
| [domains/recurring.md](domains/recurring.md) | Series and occurrences, frequency cases |
| [domains/transactions.md](domains/transactions.md) | TransactionStore CRUD, FRC, batch operations |
| [domains/voice.md](domains/voice.md) | Voice input, speech recognition, EdgeGlow and the orb |

## Product, growth, release

| File | Purpose |
|------|---------|
| [promotion-plan.md](promotion-plan.md) | The growth and MRR plan: snapshot, checklists, weekly metrics. Living doc |
| [app-marketing-context.md](app-marketing-context.md) | Facts every ASO and marketing task starts from |
| [monetization-strategy.md](monetization-strategy.md) | Tenra Pro: model, pricing, paywall strategy |
| [asc.md](asc.md) | App Store Connect and TestFlight from a cloud session (`appstore/asc.py`, workflows) |
| [releases/](releases/) | What's New per version (`1.4.md`, …) |
| [localization/README.md](localization/README.md) | Localization rules, locale status, per-locale ASO files |

## Work in flight

| File | Purpose |
|------|---------|
| [plans/README.md](plans/README.md) | Plans and findings: what landed, what is open, what was decided |
| [plans/004-spike-wallet-automation.md](plans/004-spike-wallet-automation.md) | Spike: Apple Pay logging through the Shortcuts "Wallet" automation |
| [plans/2026-10-wallet-automation-spike.md](plans/2026-10-wallet-automation-spike.md) | The spike's probe instructions and findings so far |
| [localization/phase5-voice-spike.md](localization/phase5-voice-spike.md) | Deferred: voice input and statement parsing for ja / ko |

## Archive

[archive/](archive/) holds about 450 historical files: completion reports, bug analyses,
migration guides, finished plans and specs. Their lasting rules are already in the docs above;
read them for history, not for current rules.
