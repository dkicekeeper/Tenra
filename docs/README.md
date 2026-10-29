# Tenra — Documentation

Every current document lives in `docs/`. Everything that is no longer current lives in
`docs/archive/`. [CLAUDE.md](../CLAUDE.md) routes Claude to the right file by what is being edited;
this file is the full index.

## Rules

1. **Current docs only, in `docs/`.** A document is current when it describes the app as it is
   now or work still in flight. Nothing documentation-like lives elsewhere in the repo, apart from
   the files tools require at fixed paths: `CLAUDE.md`, `AGENTS.md`, `.claude/skills/*/SKILL.md`.
2. **Flat, with two folders:** `domains/` (one file per domain) and `public/` (the GitHub Pages
   site). Everything else sits in `docs/` itself; no folder for a single kind of file.
3. **Work in flight** is a file in `docs/` while it runs: a plan (`plan-<topic>.md`), the What's
   New of the version being prepared (`release-notes.md`). Open items, ideas and decisions go in
   [backlog.md](backlog.md).
4. **Stale goes to `docs/archive/`, in the same commit that makes it stale.** A plan that landed,
   was reverted or rejected → `archive/plans/`; release notes once the version ships →
   `archive/release-notes-<version>.md`; a finished audit or report → `archive/`; a spec the code
   has moved past → `archive/specs/`, after its lasting rules are folded into the domain doc.
   Archived files are history: don't update them, don't route to them for current rules.
5. **Names: lowercase, words joined by hyphens**, for files and folders, in `archive/` too:
   `promotion-plan.md`, `performance-audit-2026-07.md`. Dates are ISO (`2026-10-09`). Exceptions:
   `README.md` and locale codes (`pt-BR.md`).
6. **No history in current docs.** "Before X it did Y", bug stories, dated audit notes and
   finished checklists belong in the commit message or the archive; a doc states what is true now.
7. **Skills that write documents elsewhere by default** (superpowers → `docs/superpowers/`,
   GSD → `.planning/`) write their plan to `docs/plan-<topic>.md` and fold lasting rules into the
   domain doc.
8. **A new document gets a row in this index**; a new domain also gets a row in the
   [CLAUDE.md](../CLAUDE.md) "When to Read Which Doc" table.

## Project-wide references

| File | Purpose |
|------|---------|
| [architecture.md](architecture.md) | MVVM + Coordinator, TransactionStore, BalanceCoordinator, Repository, CoreData v16, backups |
| [concurrency.md](concurrency.md) | Swift 6 concurrency, CoreData threading, `@Observable` rules, DataSnapshot |
| [design-system.md](design-system.md) | Tenra on DesignKit: the bridge and hooks, what stays in Tenra, screen patterns, amount formatting, dates and category styling, effects in use (tokens and components: DesignKit's own docs) |
| [gotchas.md](gotchas.md) | SwiftUI layout, performance hot paths, previews, ignorable console warnings |
| [localization.md](localization.md) | Locales, rules for changing a string, permission prompts, adding a language |

## Domains

| File | Purpose |
|------|---------|
| [domains/accounts.md](domains/accounts.md) | Account, series and parsed-date indexes, AccountDetailView read contract, ranking |
| [domains/assistant.md](domains/assistant.md) | Ten, the AI assistant: architecture, tools, reply blocks, threads and facts, "Ten writes", the server and its protocol, App Attest, limits, privacy, setup and eval |
| [domains/categories.md](domains/categories.md) | Category, subcategory and budget aggregates, style cache, reorder |
| [domains/charts.md](domains/charts.md) | Insight charts (DesignKit + `PeriodChartAdapters.swift`), scrolling, sparklines |
| [domains/csv.md](domains/csv.md) | CSV import/export round-trip rules |
| [domains/currency.md](domains/currency.md) | FX rates, providers, prewarm, base-currency aggregation |
| [domains/deposits.md](domains/deposits.md) | Interest accrual, capitalization, account ↔ deposit conversion |
| [domains/goals-and-debts.md](domains/goals-and-debts.md) | Savings goals and personal debts: storage (v15), saved amount and progress, settling, the Pro gate, screens |
| [domains/import.md](domains/import.md) | Statement and receipt recognition, DocumentSnapshot seam, Apple Intelligence policy |
| [domains/insights.md](domains/insights.md) | InsightsService, DataSnapshot, PreAggregatedData, signal notifications, the metric catalogue |
| [domains/intents.md](domains/intents.md) | App Intents and Siri, App Shortcuts, the Wallet automation and merchant memory |
| [domains/loans.md](domains/loans.md) | Payments, linking, amortization |
| [domains/logos.md](domains/logos.md) | Logo provider chain, ServiceLogoRegistry |
| [domains/recurring.md](domains/recurring.md) | Series and occurrences, frequency cases |
| [domains/transactions.md](domains/transactions.md) | TransactionStore CRUD, FRC, batch operations |
| [domains/voice.md](domains/voice.md) | Voice input, speech recognition, draft resolution, EdgeGlow and the orb |

## Product and release

| File | Purpose |
|------|---------|
| [promotion-plan.md](promotion-plan.md) | The product, Tenra Pro and the growth plan: facts, releases, decisions, channels, weekly metrics. Living doc |
| [asc.md](asc.md) | App Store Connect and TestFlight from a cloud session (`appstore/asc.py`, workflows) |
| [backlog.md](backlog.md) | Open items, ideas not planned yet, decisions that stand |
| [plan-ads-readiness.md](plan-ads-readiness.md) | Plan in flight from the product audit of 2026-10-22: 1.7 ready for paid traffic shipped on 2026-10-24 (ASA attribution, onboarding sells auto-capture, iCloud backups by default and restore on the welcome screen, the store page and an "Auto-capture" custom page, with the widgets, Kazakh and money for today planned for 1.8); still open: the ASA launch in KZ and what it waits on, bank notifications part two, the server before traffic, then 1.8+; the owner's decisions D0-D9 |
| [plan-assistant-ios27.md](plan-assistant-ios27.md) | Plan, not started: Ten on Apple's models (Private Cloud Compute, on device) behind a router, and Siri on iOS 27 |
| [plan-notification-capture.md](plan-notification-capture.md) | Plan in flight: expenses and incomes from any bank's push notifications through iOS 27's notification trigger (`LogBankNotificationIntent`, the bank-agnostic `BankNotificationParser`, recorded through the Wallet path), own-account transfers and the setup guide: in 1.7, checked on the owner's phone, not yet in What's New; learned templates, "Unparsed" and the Apple model layer still ahead |
| [plan-assets.md](plan-assets.md) | Plan, owner's decisions taken 2026-10-16, not started: assets (real estate, vehicles) with market valuations, rent and upkeep, and net worth |
| [plan-investments.md](plan-investments.md) | Plan, owner's decisions taken 2026-10-16, not started: investment portfolios (KASE and US stocks, ETFs, crypto on exchanges and wallets), quote sources and their licences, read-only exchange keys, purchases in parts (trade journal, average cost, XIRR), what Ten may and may not say about investments |
| [public/](public/) | The support site: privacy policy, terms of use, support (GitHub Pages) |

## Archive

[archive/](archive/) holds about 470 historical files: completion reports, bug analyses,
migration guides, finished plans and specs, the July 2026 localization plan, earlier versions of
the product docs. Their lasting rules are already in the docs above; read them for history, not
for current rules.
