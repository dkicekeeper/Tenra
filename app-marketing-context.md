# Tenra — App Marketing Context

> Foundation document for all ASO / marketing work. Update when facts change.
> Created: 2026-07-17 (from ASC API + repo docs).

## App Overview
- **App Name:** Tenra: Budget, Expense Tracker
- **App ID (Apple):** 6761530361
- **Bundle ID:** dakacom.Tenra
- **Category:** Finance
- **Platform:** iOS only, iPhone-only (iPad planned in 1.1, not shipped yet)
- **Price Model:** Freemium + Subscription (Tenra Pro) + Lifetime IAP
- **Launch Date:** ~April 2026 (v1.0 READY_FOR_SALE)
- **Current Version:** 1.0.2 (READY_FOR_SALE since 2026-07-14); 1.1 in PREPARE_FOR_SUBMISSION (Siri / App Intents, created 2026-07-31)
- **Monetization live since:** ~2026-07-09 (1.0.1 build 4 approved after one rejection)

## Value Proposition
- **Problem:** people don't see where their money goes; bank-sync finance apps demand credentials and feel unsafe (esp. in CIS).
- **Target Audience:** RU-speaking users in KZ + diaspora (phase 1), global iOS users wanting a private, manual-first tracker (phase 2). Multi-currency holders (KZT/RUB/USD/EUR).
- **Unique Differentiator:** 100% private (local + iCloud, no bank login), native iOS 26 Liquid Glass design, voice input, PDF statement import, deposits & loans with real interest math, honest multi-currency (real FX).
- **Elevator Pitch:** the beautiful, private money tracker: log by voice, see where money goes, no bank login needed.

## Competitors
| App | Market | Strengths | Weaknesses |
|-----|--------|-----------|------------|
| CoinKeeper | CIS | brand, lifetime anchor | dated UI, pushes paid hard |
| Zenmoney (Дзен-мани) | CIS | bank sync | trust/privacy concerns, sub fatigue |
| Monefy | global/CIS | simplicity | no depth, no recurring revenue |
| YNAB | global | brand, methodology | $109/yr, no free tier, US-centric |
| Monarch Money | US | full-featured | $99.99/yr, bank-login only |
| Wallet by BudgetBakers / Spendee | global | bank sync | generic design, sub fatigue |

## Current ASO State (2026-07-17)
- **Title (US):** Tenra: Budget, Expense Tracker (30/30)
- **Subtitle (US):** Money Manager & Subscriptions
- **Title (RU/KZ):** Tenra: Бюджет, Учёт Расходов
- **Subtitle (RU/KZ):** Финансы, подписки и контроль
- **Keywords:** see docs/RELEASE_1.1_PLAN.md (locked 1.0 set; volume-unvalidated guesses). 1.1 appends `siri` only where it fits free (en-US, ru, ja, ko); the other 9 locales are already at the 100-char cap and no existing keyword was sacrificed for it.
- **ASC metadata locales:** 13 (de-DE, en-US, es-ES, es-MX, fr-CA, fr-FR, it, ja, ko, pt-BR, ru, tr, uk), all with description+keywords+promo text
- **In-app locales:** 11 (en, ru, de, es, fr, tr, pt-BR, it, uk, ja, ko)
- **Rating:** 0 written reviews worldwide, all time (as of 2026-07-17). CRITICAL GAP.
- **Rating prompt:** RatingPromptService live since 1.0.1 (sessions ≥ 3, tx ≥ 5, days ≥ 3)

## Monetization (live)
- Subscription group "Tenra Pro" (id 22162218): `tenra.pro.monthly` (1 490 ₸), `tenra.pro.annual` (4 990 ₸, 14-day free intro) — both APPROVED; `tenra.pro.lifetime` non-consumable (~11 900 ₸).
- RevenueCat: entitlement `pro`, offering `default`, paywall configured in dashboard.
- Free tier: 3 accounts, manual tracking, basic features. Gated: 4th account, voice, PDF/CSV import, deposits, loans. Insights deliberately free (aha-moment) with soft paywall (3-show/14-day cap).
- Founding Users grandfathered (pre-Pro installs).
- Subscriptions available in 175 territories incl. Kazakhstan (verified 2026-07-17 in ASC).
- Small Business Program: enrolled (2026-07-17) → 15% commission. DSA trader status submitted 2026-07-17, pending Apple review.

## Goals
1. **MRR growth** — from ~0 to first $200-500 MRR by end of Q3 2026, via conversion fixes + ASA pilot.
2. **Social proof** — 25+ ratings, avg ≥ 4.5 in KZ + US by mid-August 2026.
3. **Measurement** — full funnel numbers (impressions → page views → installs → trials → paid) visible weekly.

## Resources
- **Budget:** indie; ASA pilot budget ~$300-500/mo to start (adjustable).
- **Team:** solo developer + Claude.
- **Tools:** App Store Connect API (asc-mcp; vendor number 94171379 configured 2026-07-17), RevenueCat (source of truth for MRR/trials), Analytics Reports API ONGOING request created 2026-07-17 (id ece7a22d-…, data ready ~24-48h after creation).
- **Baseline (2026-07-17, Sales API):** Apr-May 2026 zero units; June: 17 new downloads (KZ 11, RU 3); week ending Jul 5: 8 new; week ending Jul 12: 1 new. Proceeds $0, zero subscription purchases. ~40 installs lifetime.
- **Constraints:** no MMP, no ATT prompt (App Privacy: Data Not Collected) → Meta/TikTok ads impractical for now; ASA works without ATT (AdServices).

## Markets
- **Primary:** Kazakhstan (KZ), RU-speaking.
- **Secondary:** US + EN; then EU (de/fr/es/it), TR, BR, UA, JP, KR (metadata already localized).
- **Storefront risk:** Russia IAP unreliable post-2022; do not spend ad budget there.

## Key References
- Monetization strategy: docs/MONETIZATION_STRATEGY.md
- Old 1.1 release plan (iPad + rating prompt + ASO iteration): docs/RELEASE_1.1_PLAN.md
- **Active promotion plan: docs/PROMOTION_PLAN.md**
- Screenshot pipeline: -ScreenshotDemo scheme + capture_screenshots.sh + Figma "Screenshots L10n"
- Legal: dkicekeeper.github.io/Tenra/{terms-of-use,privacy-policy,support}.html
