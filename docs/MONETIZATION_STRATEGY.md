# Tenra — Monetization Strategy

**Status**: Draft v1 · **Date**: 2026-06-16
**Context**: Launched, has users, $0 revenue. Market: CIS now → global later. Priority: growth + soft monetization.

---

## 1. Recommended Model: Freemium + Subscription (soft paywall)

Tenra is a habit app (daily money logging) with deep power features. That profile fits **freemium subscription** better than paid-upfront, ads, or one-time IAP:

- Daily logging must stay frictionless → the core loop is **free** (drives retention + word-of-mouth, which matters most given "growth first").
- Depth features (insights, multi-currency, imports, voice, cloud) carry real ongoing value and server/API cost → **subscription**.
- Recurring revenue + high LTV is the only model that scales from CIS to global without re-architecting.

Add a **Lifetime** tier as a secondary option — CIS users are subscription-averse and respond well to one-time "buy it forever" pricing. It also gives early cash flow.

**Avoid**: ads (kills trust in a finance app, low ARPU in CIS), paid-upfront (blocks the growth goal), pure IAP unlocks (no recurring revenue).

---

## 2. Competitor Landscape

### CIS / RU-speaking market

| App | Model | Monthly | Annual | Lifetime | Notes |
|-----|-------|---------|--------|----------|-------|
| **CoinKeeper** | Freemium sub | ~299 ₽ | ~899 ₽ | ~1990 ₽ | Lifetime is the anchor they push hardest |
| **Дзен-мани (Zenmoney)** | Freemium, packages | from ~99 ₽ | — | — | Bank-sync is the paid hook |
| **Moneon** | Freemium sub | low | low | — | Visual-first, weak depth |
| **Monefy** | Paid Pro (IAP) | — | — | one-time | Simplicity-only; no recurring revenue |

**Takeaways for CIS**: price points are low (₽99–299/mo, ₽899/yr), lifetime is a real expectation, and bank-sync / depth is the standard paid hook. Don't anchor to USD benchmarks here.

### Global market (for phase 2)

| App | Monthly | Annual | Model |
|-----|---------|--------|-------|
| **YNAB** | $14.99 | $109 | Sub-only, no free tier, 34-day trial |
| **Monarch Money** | — | $99.99 | Sub-only |
| **Wallet (BudgetBakers)** | mid | mid | Freemium + bank sync |
| **Spendee** | mid | mid | Freemium, bank sync + exports paywalled |
| **EveryDollar** | — | $79.99 | Freemium → premium |
| **PocketGuard** | — | $74.99 | Freemium → premium |

**Takeaways for global**: Tenra can price *below* YNAB/Monarch as the "private, no-bank-login, beautiful native iOS" alternative. $24.99–$29.99/yr is a strong value-anchored position.

### Tenra's differentiation (lead with these in the paywall)

- Native iOS 26 / Liquid Glass design — feels premium vs. cross-platform competitors.
- **Privacy**: 100% local + iCloud, no bank-login required (big trust win in CIS).
- Voice input, PDF statement import, deposits & loans tracking — depth most rivals lack.
- Multi-currency done properly (real FX) — relevant for CIS users holding KZT/RUB/USD.

---

## 3. Free vs. Premium Split

Principle: **the daily loop is free, depth + scale + automation is paid.** Gating the daily loop would kill the growth goal.

### Free (the hook — keep generous)
- Unlimited manual transactions
- Up to **3 accounts**
- All default categories + basic custom categories
- Balance, history, basic monthly summary
- Recurring / subscription tracking (basic)
- Single base currency
- Local data + manual iCloud backup

### Premium ("Tenra Pro")
- **Unlimited accounts**
- **Insights** — full advanced analytics (the headline benefit)
- **Multi-currency + live FX**
- **Voice input**
- **PDF bank-statement import** + **CSV import/export**
- **Deposits & Loans** advanced tracking (interest, amortization)
- **Budgets** (or advanced budgets) per category
- **Auto iCloud sync** across devices
- Custom icons/colors beyond free limit, future widgets/themes

> Tuning knob: if conversion is low, move **Budgets** or **multi-currency** into Premium more strictly. If retention/growth suffers, loosen the account limit (3 → 5). Decide with data, not upfront.

---

## 4. Pricing

### CIS (launch)

| Tier | Price | Framing |
|------|-------|---------|
| Monthly | **1 490 ₸ / ~290 ₽ / $2.99** | Anchor only — make it look expensive next to annual |
| **Annual (hero)** | **4 990 ₸ / ~990 ₽ / $19.99** | "≈96 ₸/неделя · экономия 65%" |
| Lifetime | **11 900 ₸ / ~2 490 ₽ / $39.99** | "Один раз — навсегда" (≈2.4× annual) |

- **7-day free trial** on the annual plan (the default-selected option).
- All prices `.99`-style locally (1 490, 4 990, 11 900 read clean in ₸).

### Global (phase 2, localized via App Store pricing tiers)

| Tier | Price |
|------|-------|
| Monthly | $4.99 |
| Annual (hero) | $29.99 (save ~50%) |
| Lifetime | $59.99 |

Let App Store Connect auto-localize to RUB/EUR/etc. via price tiers — don't hardcode currency.

---

## 5. Paywall Design

### Timing — soft paywall after the aha-moment (NOT on onboarding)

Given "growth first," do **not** hard-gate at onboarding. Use two triggers:

1. **Aha-moment soft paywall** (dismissible): first time the user opens **Insights**, or after logging ~10 transactions / reaching the end of their first week. This is where they *feel* the value ("вот куда уходят деньги").
2. **Feature-gate paywall** (contextual): when they tap a Premium feature (add 4th account, voice input, PDF import, multi-currency). Highest-intent, highest-converting moment.

Always include a visible close button (Apple requirement + trust).

### Structure (top → bottom)

1. **Headline** — benefit, not "Перейти на Премиум". E.g. *"Видьте, куда уходят деньги — и контролируйте бюджет"*.
2. **3–5 benefits** (outcomes, not features): полная аналитика · мультивалюта · импорт выписок · безлимит счетов · синхронизация.
3. **Social proof** — rating + user count + 1 short testimonial.
4. **Pricing** — annual pre-selected & highlighted, monthly shown as anchor, lifetime as third option.
5. **CTA** — *"Попробовать 7 дней бесплатно"* (not "Оформить подписку").
6. **Restore purchases** + small print (auto-renew terms, links to Terms/Privacy).

### What converts (apply these)
- Show what's locked: blurred Insights charts behind the paywall with "Разблокировать".
- Display annual savings % prominently.
- With/without comparison row (Free vs Pro).
- "No commitment" trial messaging + easy cancel info.

---

## 6. Trial Strategy

- **7 days** (standard, good balance for a weekly-habit app).
- Value reminders via local notifications: Day 1 ("ваш первый отчёт готов"), Day 3, Day 5/6 ("осталось 2 дня — вот что вы потеряете": list their own logged data behind a lock).
- Offer a one-time discounted first period if trial is dismissed without converting.

---

## 7. Existing Users — Grandfathering (critical, you have a live base)

- **Grandfather all current users**: anyone who installed before the Pro launch date gets a permanent "Founding User" entitlement to current Premium features (or at minimum a generous free perk).
  - Implement via a one-time `UserDefaults`/CoreData flag set on first launch of the Pro build for users with `installDate < launchDate`, OR a non-consumable "founder" entitlement.
- Announce it as a gift ("спасибо, что были с нами с самого начала"). Converts goodwill → reviews & referrals, and avoids the #1 freemium-introduction mistake: angering existing users by yanking features they already use.
- New features added *after* launch can still be Pro-only for grandfathered users — be explicit about the boundary.

---

## 8. Implementation Roadmap

### Tech choice: **RevenueCat** (recommended over raw StoreKit 2)
- Free up to $2.5k/mo tracked revenue — zero cost at your stage.
- Built-in paywall A/B testing, trial/entitlement management, cross-platform when you add Android, and analytics (trial-to-paid, churn) you'd otherwise build by hand.
- Wraps StoreKit 2; you keep native receipt validation without writing it.
- ⚠️ **Russia payment risk**: Apple IAP reliability in the RU App Store is degraded post-2022. Validate that IAP completes for RU accounts in sandbox; Kazakhstan (KZT) works normally. Consider leading the launch in KZ + global RU-speaking diaspora.

### Phases

**Week 1 — Foundation**
- Add RevenueCat SDK; configure products (monthly/annual/lifetime) in App Store Connect.
- Define `Entitlement.pro`; central `PremiumGate` service (single source of truth for `isPro`).
- Implement grandfathering flag for existing users.

**Week 2 — Gating + Paywall**
- Wire feature gates: account limit, Insights, voice, imports, multi-currency, budgets.
- Build the paywall view (reuse `FinanceCard`/design tokens — see design-system.md). Annual pre-selected.
- Soft-paywall trigger on Insights / Nth-transaction; feature-gate triggers on Pro taps.

**Week 3 — Trial + Lifecycle**
- 7-day trial flow + local-notification value reminders.
- Restore purchases, manage-subscription deep link, paywall close handling.
- QA in StoreKit sandbox (trial, renew, cancel, restore, lifetime, grandfathered user).

**Month 1 — Optimize**
- Launch to 100%. Track trial-start, trial-to-paid, conversion, ARPU.
- A/B test (RevenueCat): paywall headline, annual price (test 4 990 vs 5 990 ₸), trigger timing.

**Month 2+ — Expand**
- Localize global pricing tiers; soft-launch English paywall to non-CIS.
- Add annual upsell to monthly subscribers; win-back offers for churned/expired trials.
- Consider referral perk (1 free month) to compound the growth goal.

---

## 9. Targets & Metrics

| Metric | Target (realistic for CIS freemium) |
|--------|-------------------------------------|
| Free → Paid conversion | 2–4% |
| Trial-to-Paid | 40–55% |
| Annual share of subscribers | > 60% (push hard) |
| ARPPU | depends on annual mix; aim 3–6× ARPU |
| LTV | must exceed CAC (ASA in CIS is cheap — favorable) |

Instrument from day one: trial starts, conversions by trigger (soft vs feature-gate), paywall view→purchase, churn. You can't optimize what you don't measure.

---

## 10. The One-Paragraph Summary

Launch **Tenra Pro** as a freemium subscription: keep daily logging + 3 accounts free to protect growth; gate Insights, multi-currency, voice, imports, deposits/loans, unlimited accounts, and auto-sync behind Pro. Price for CIS at **4 990 ₸/year (hero, 7-day trial)** with 1 490 ₸/mo as an anchor and 11 900 ₸ lifetime for subscription-averse users. Show a **soft, dismissible paywall after the aha-moment** (first Insights open) plus contextual feature-gates. **Grandfather all existing users** as Founding Users to convert goodwill into reviews and referrals. Build on **RevenueCat** for paywall A/B testing and zero upfront cost. Optimize annual share and trigger timing with data over the first two months, then localize pricing and roll the paywall out globally.

---

### Sources
- [CoinKeeper vs Дзен-мани — picktech.ru](https://picktech.ru/catalog/personal-finance-software/compare/coinkeeper-vs-dzen-mani/)
- [Дзен-мани цены/функции — a2is.ru](https://a2is.ru/catalog/uchyot-lichnykh-finansov/zen-money)
- [Zenmoney vs CoinKeeper — startpack.ru](https://startpack.ru/compare/zenmoney/coinkeeper)
- [Wallet by BudgetBakers — Everything about Premium](https://support.budgetbakers.com/hc/en-us/articles/7151349344018-Everything-about-Premium)
- [Monefy vs Wallet — slant.co](https://www.slant.co/versus/2887/2901/~monefy-money-manager_vs_wallet-by-budgetbakers)
- [YNAB Pricing 2026 — checkthat.ai](https://checkthat.ai/brands/ynab/pricing)
