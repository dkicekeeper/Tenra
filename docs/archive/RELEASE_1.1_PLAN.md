# Tenra — Release 1.1 Plan

> ⚠️ **Superseded for the version number.** 1.1 now ships App Intents / Siri
> (see docs/superpowers/plans/2026-07-31-app-intents.md). The iPad workstream
> below moves to **1.2**. Workstreams B and C remain valid as written.


> Status: planning. Start after 1.0 is approved on the App Store.
> Goal: first post-launch update — bring back iPad properly, ship the rating-prompt
> growth loop, and iterate ASO on real keyword data.

Three independent workstreams; can run in parallel.

---

## Workstream A — iPad adaptation (main effort)

1.0 shipped as iPhone-only (`TARGETED_DEVICE_FAMILY = "1"`) because the UI stretched on
13″ iPad. 1.1 brings iPad back **properly**, not stretched.

**Tasks:**
1. Re-enable iPad: set `TARGETED_DEVICE_FAMILY = "1,2"` in `Tenra.xcodeproj/project.pbxproj`.
2. Constrain content width on regular size class — add a `.readableContentWidth(max: ~700)`
   modifier/token in `Utils/`, apply to root scroll views (Home, Analytics, Finances,
   detail screens). Centers content in a column like native iPad apps; kills the stretch.
3. Adaptive grids — convert category / Finances grids to `LazyVGrid(columns: adaptive)`
   keyed on `@Environment(\.horizontalSizeClass)`; iPhone 3 cols, iPad more but with a
   sensible cell `maximum` so icons don't balloon.
4. (Optional, larger) Consider `NavigationSplitView` for iPad (list left / detail right).
   This is "real" iPad — sizeable scope; can defer to 1.2. For 1.1, readable width is enough.
5. Test on iPad Pro 11″ + 13″ and Split View (1/2, 1/3) — no clipping.
6. Produce iPad 13″ screenshots (2064×2752) with populated data — 5–6 frames.

**Definition of done:** content not stretched on 13″, grids adaptive, Split View intact.

---

## Workstream B — Rating prompt strategy ✅ (implemented)

Already built (see commit "Add rating-prompt strategy"). Just ships in 1.1.

Files:
- `Services/Settings/RatingPromptService.swift` — session/tx/install-date counters,
  eligibility rules, native `AppStore.requestReview(in:)`.
- `Views/Components/Feedback/RatingSurveyView.swift` — neutral pre-prompt survey.
- Hooks: `TenraApp.swift` (recordSession on `.active`),
  `TransactionsViewModel.addTransaction` (recordTransactionAdded on success),
  `MainTabView.swift` (`.sheet` driven by `shouldShowSurvey`).
- Strings: `rating.survey.*` in en + ru.

Thresholds (tunable at top of `RatingPromptService`): sessions ≥ 3, transactions ≥ 5,
days since install ≥ 3, not already prompted on this version.

Flow: success moment (5th tx) → "Enjoying Tenra?" → Yes = native prompt /
Not really = mailto feedback (dakacom@gmail.com), no native prompt.

**Post-release:** monitor first ratings + average. Future: add a 2nd success moment
(after a positive financial insight / budget headroom).

---

## Workstream C — ASO iteration on data (no code)

1. Run keyword research (KZ + US) for: бюджет / учёт расходов / подписки / финансы /
   трекер (RU) and budget / expense tracker / money manager / subscriptions (EN).
   Current subtitle/keywords are product-logic guesses, not volume-backed.
2. Tune subtitle + keyword field in 1.1 based on results (metadata changes don't need a
   new build, but convenient to sync with the release).
3. Add 2 missing screenshots to BOTH storefronts:
   - "Add expenses by voice" / «Добавляйте траты голосом» — top differentiator, currently absent.
   - "USD, EUR, KZT — one true total" / «KZT, USD, EUR — один честный итог» — multi-currency.
4. Replace the "alarming" frame (where Доходы 0 ₸ ↓100%) with a month that has non-zero income.
5. Promotional Text for 1.1: "Now on iPad" / «Теперь и на iPad».

### Locked 1.0 metadata (reference — KZ/RU storefront)
- Title: `Tenra: Бюджет, Учёт Расходов` (28/30)
- Subtitle: `Финансы, подписки и контроль` (28/30)
- Keywords: `трата,деньги,кошелёк,накопление,счёт,долг,кредит,депозит,валюта,планировщик,копилка,доход,тенге` (95/100)

### Locked 1.0 metadata (reference — US storefront)
- Title: `Tenra: Budget, Expense Tracker` (30/30)
- Subtitle: `Money Manager & Subscriptions` (29/30)
- Keywords: `finance,spending,bill,saving,planner,wallet,cash,debt,loan,deposit,account,currency,daily,saver` (95/100)

### Screenshot captions (locked 1.0 order, RU)
1. Главная — Бюджет по каждой категории / Лимиты, траты и остаток на месяц — сразу на главном экране
2. Финансы — Все ваши финансы в одном месте / Счета, депозиты, подписки и кредиты — без привязки банка
3. Аналитика — Видно, куда уходят деньги / Баланс, расходы и чистый поток за месяц — с первого взгляда
4. Финансовый скор — Оценка вашего финансового здоровья / Сбережения, бюджеты и подушка в одном понятном балле
5. Топ категория — Узнайте свои главные траты / Категории расходов с наглядной разбивкой по месяцам
6. История — Каждая операция под контролем / Траты, доходы и проценты по депозитам — в одной ленте

---

## Workstream D — polish (optional)
- Russian Privacy Policy on the same hosted page (currently EN only).
- 2nd rating success moment (see B).
- Audit other tx-add paths bypassing `TransactionsViewModel.addTransaction`
  (e.g. `AccountActionViewModel.saveTransaction`) if they should count toward rating eligibility.

---

## 1.1 submission checklist
- [ ] Build `1.1 (1)` — bump `MARKETING_VERSION = 1.1`, reset `CURRENT_PROJECT_VERSION = 1`
- [ ] iPad 13″ screenshots uploaded (Universal again → required)
- [ ] What's New: "iPad support. Improvements and stability." (EN + RU)
- [ ] Metadata updated per keyword research
- [ ] Tested on real iPhone + iPad

---

## Recommended sequence
1. Wait for 1.0 approval (don't run parallel releases — keeps statuses clean).
2. While waiting — Workstream C (keyword research + prep 2 new frames): no code.
3. After approval — Workstream A (iPad), the main dev effort.
4. Bundle into 1.1 build, run checklist, submit.

---

## App Store Connect reference (set up for 1.0)
- Privacy Policy URL: https://dkicekeeper.github.io/Tenra/privacy-policy.html
- Support URL: https://dkicekeeper.github.io/Tenra/support.html
- Terms of Use URL: https://dkicekeeper.github.io/Tenra/terms-of-use.html
- Contact / feedback email: dakacom@gmail.com
- Legal pages source: `docs/public/` (deployed to GitHub Pages via `.github/workflows/static.yml` on push to `main`)
- App Privacy: Data Not Collected (local-only storage)
- Category: Finance · Localizations: EN + RU · Storefronts: KZ + US
