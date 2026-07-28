# Tenra — Documentation

Living reference docs. The thin index in [CLAUDE.md](../CLAUDE.md) routes Claude to specific files based on what's being edited.

## Top-Level References

| File | Purpose |
|------|---------|
| [architecture.md](architecture.md) | MVVM+Coordinator deep dive, TransactionStore, BalanceCoordinator, Repository pattern, CoreData v12 |
| [concurrency.md](concurrency.md) | Swift 6 concurrency, CoreData threading, @Observable rules |
| [design-system.md](design-system.md) | Design tokens, components, animations, padding contract, amount formatting |
| [gotchas.md](gotchas.md) | SwiftUI Layout, Performance hot-paths, code hygiene |
| [INSIGHTS_METRICS_REFERENCE.md](INSIGHTS_METRICS_REFERENCE.md) | Per-metric reference for InsightsService (formulas, granularity, data sources) |

## Domain Files

| File | Purpose |
|------|---------|
| [domains/transactions.md](domains/transactions.md) | TransactionStore CRUD, FRC, batch operations, predicate gotchas |
| [domains/insights.md](domains/insights.md) | InsightsService architecture, DataSnapshot, PreAggregatedData |
| [domains/deposits.md](domains/deposits.md) | Interest accrual, capitalization, account ↔ deposit conversion |
| [domains/loans.md](domains/loans.md) | Payment tracking, reconciliation, amortization |
| [domains/recurring.md](domains/recurring.md) | Series + occurrences, frequency cases |
| [domains/charts.md](domains/charts.md) | Swift Charts patterns, scrollable, mini-charts |
| [domains/csv.md](domains/csv.md) | CSV round-trip rules |
| [domains/voice.md](domains/voice.md) | VoiceInput architecture, speech recognition |
| [domains/currency.md](domains/currency.md) | FX rates, providers, prewarm |
| [domains/logos.md](domains/logos.md) | Logo provider chain, ServiceLogoRegistry |

## Working Files

- `plans/` — implementation plans from `/ship` sessions, **in flight only**. Completed plans move to `archive/plans/`.

Feature specifications live alongside their plans in `archive/specs/`.

## Archive

`archive/` contains ~305 historical docs from completed phases. These are completion reports, bug analyses, and migration guides whose key rules have been distilled into the active docs above and `MEMORY.md`.

## Adding to These Docs

When working on a new pattern or rule that should be remembered:

1. **If it's a project-wide rule (cross-domain)** → add to the matching top-level doc (`architecture.md`, `concurrency.md`, `design-system.md`, `gotchas.md`)
2. **If it's domain-specific** → add to the matching `domains/<name>.md`
3. **If a new domain emerges** → create `domains/<new>.md`, add row to:
   - This file's "Domain Files" table
   - [CLAUDE.md](../CLAUDE.md) "When to Read Which Doc" trigger table
   - [CLAUDE.md](../CLAUDE.md) "Reference Docs Index"
4. **If it's a "red flag" (silent data corruption / crash)** → add bullet to [CLAUDE.md](../CLAUDE.md) "Critical Red Flags" section AND domain doc

Keep [CLAUDE.md](../CLAUDE.md) thin — it's loaded into every session's context. Detailed rules live in domain docs.
