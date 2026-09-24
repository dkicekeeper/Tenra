# Audit 2026-09-24 (part 2): security, performance, tests, layout, deposit/loan math, voice, paywall, translations

Written by the improve skill (deep) against commit `a57d5fe4`, after part 1
(`plans/AUDIT-2026-09-24-product-defects.md`). Every finding was confirmed by reading
the cited code; line numbers are as of that commit. Plans: `plans/012`–`plans/019`.

## Findings table (ordered by leverage)

| # | Area | Finding | Impact | Effort | Conf. | Plan |
|---|---|---|---|---|---|---|
| V1 | Voice | Russian voice keywords for the most common spending ("кофе", "обед", "ресторан", "доставка", "магазин", "одежда") point to categories onboarding never creates ("Еда", "Покупки") and end up in "Прочее"; voice tests seed a fake "Еда" category, so they pass | primary market, Pro feature | S | HIGH | 012 |
| O1 | Onboarding / voice | Onboarding creates expense categories only; a new user's first income dead-ends ("Create categories first", no button), and voice "зарплата" has no target | every new user | S-M | HIGH | 013 |
| S1 | Security | No App Intent sets `authenticationPolicy`, so Siri answers "how much did I spend" on a locked iPhone; the new app lock does not cover Siri | privacy positioning | S | MED-HIGH | 014 |
| T10n1 | Translations | No `InfoPlist.strings` in any locale: camera, microphone, speech, Face ID prompts are English for all 11 locales; `NSUserNotificationUsageDescription` is a Russian string on a key iOS does not use | every non-English user at first voice/scan | S | HIGH | 015 |
| R1 | Recurring math | Occurrences step from the previous date (+1 month), so a series on the 29th–31st drifts to the 28th forever after February; reminders compute from the start date and fire on a different day | subscriptions/salary on 29–31 | M | HIGH | 016 |
| LN1 | Loan math | The amortization schedule replays history with the CURRENT monthly payment; after a "reduce payment" early repayment every past row is wrong, and `markPaymentsPaid` writes the wrong `remainingPrincipal` (loan balance) from it | Pro loan users | M | HIGH | 017 |
| LN2 | Loan math | `nextPaymentDate` for payment day 29–31 lands on the 28th/30th after a short month, and treats a payment due today as already passed | Pro loan users | S | HIGH | 017 |
| L1 | Layout | `CategorySelectorView` fixes each chip to 80 pt with a one-line 18 pt label: "Кафе и рестораны", "Коммунальные", "Lebensmittel" truncate on add/edit/voice/receipt screens | all locales but EN mostly | S | MED (verify visually) | 018 |
| T1 | Tests | Core flows have no tests: `TransactionAddCoordinator`, `TransactionEditCoordinator` (0), `SubscriptionNotificationScheduler` (0), `WeeklyDigestScheduler` (0), `PremiumManager` founder logic (0). The rating counter bug of 24.09 lived in the add coordinator | maintenance / regressions | M | HIGH | 019 |
| DP1 | Deposit math | Deposits converted before the `conversionTimestamp` fix still double-count inherited history; the documented "one-shot recovery" was never implemented | users who converted early (likely the founder) | M | HIGH (doc + grep) | not planned (investigate with real data) |
| P1 | Performance | `TransactionEditCoordinator.availableCategories` scans all transactions on every body evaluation (each calculator key press) and also offers orphaned names that then fail `validate` | edit screen | S | HIGH | not planned |
| P2 | Performance | `SubscriptionDetailView.linkedTransactionCount` scans all transactions per render; `transactionsBySeriesId` index exists | subscription detail | S | HIGH | not planned |
| PW1 | Paywall | `isSubscriber` starts false every launch until RevenueCat answers; paying subscribers can see locked Voice/Import tabs flash, and cold Siri/intent paths may treat them as free | subscribers | S | MED | not planned |
| S2 | Security | iCloud backups are unencrypted SQLite in a user-visible iCloud Drive folder (`NSUbiquitousContainerIsDocumentScopePublic = true`) | privacy positioning | M | HIGH | not planned (design decision) |
| S3 | Security | Logo lookups send brand names/domains to Google favicons and logo.dev | privacy label consistency | S | MED | not planned |
| DP2 | Deposit math | Daily interest divides by 365 in leap years too | cents | S | HIGH | not planned |

## Evidence (planned findings)

**V1.** `Tenra/Services/Voice/VoiceInputParser.swift` `categoryMap` (from line 84): 15 keys target
`"Еда"` (кафе, кофе, ресторан, обед, ужин, завтрак, еда, столовая, доставка×4, курьер×2,
еда доставка), 5 keys target `"Покупки"` (магазин, покупка, шопинг, одежда, обувь), 4 target
`"Зарплата"`. The Russian onboarding presets are `Продукты`, `Кафе и рестораны`, `Одежда`, ...
(`Tenra/ru.lproj/Localizable.strings`, `onboarding.preset.*`); none is "Еда"/"Покупки", and no income
preset exists. `TransactionDraftService.resolveCategory` then falls back to the localized "Other".
All other 86 targets equal a preset name in some locale (script check). `TenraTests/Services/Voice/VoiceInputParserTests.swift:43-55`
seeds categories "Транспорт", "Еда", "Продукты", which hides the problem.

**O1.** `CategoryPreset.defaultExpense` is the only catalog (`Tenra/Services/Onboarding/CategoryPreset.swift`);
`OnboardingViewModel.finish()` creates only selected presets (`Tenra/ViewModels/OnboardingViewModel.swift:142-151`).
`AccountActionViewModel` refuses to save income without an income category
(`Tenra/ViewModels/AccountActionViewModel.swift:259-263`), and `AccountActionView` shows only a
message in the empty state (`Tenra/Views/Accounts/AccountActionView.swift:155-165`); `CategoryCardSelectorView`
has no empty-state action.

**S1.** `grep -rn authenticationPolicy Tenra` → none. `CheckSpendingIntent` (`Tenra/Intents/CheckSpendingIntent.swift:46`)
runs in the background and speaks the total. Apple's default policy is `.alwaysAllowed`.

**T10n1.** `ls Tenra/*.lproj` shows only `Localizable.strings`, `Localizable.stringsdict`,
`AppShortcuts.strings`. Usage strings live only in `Tenra/Info.plist` (English; the notification one is Russian).

**R1.** `RecurringTransactionGenerator.calculateNextDate` adds one period to the previous
date (`Tenra/Services/Recurring/RecurringTransactionGenerator.swift:235-249`); both
`generateTransactions` (loop from line 111) and `generateUpToNextFuture` (resumes from the latest
occurrence, lines 290-300) use it. `SubscriptionNotificationScheduler.calculateNextChargeDate`
(`Tenra/Services/Notifications/SubscriptionNotificationScheduler.swift:159-227`) computes
`start + (n+1) periods`. Calendar clamps Jan 31 + 1 month to Feb 28, so the generator continues
Mar 28, Apr 28..., while reminders target Mar 31, Apr 30.

**LN1.** `LoanPaymentService.applyEarlyRepayment` overwrites `loanInfo.monthlyPayment` for
`.reducePayment` (`Tenra/Services/Loans/LoanPaymentService.swift:205-211`).
`generateAmortizationSchedule` replays from `originalPrincipal` using that CURRENT payment for every
month (`:68-122`). `LoansViewModel.markPaymentsPaid` sets `remainingPrincipal` and `totalInterestPaid`
from the schedule rows (`Tenra/ViewModels/LoansViewModel.swift:259-275`), and the loan account balance
derives from `remainingPrincipal` (CLAUDE.md Red Flag 8).

**LN2.** `LoanPaymentService.nextPaymentDate` (`:138-152`) clamps the day in the current month, then
adds one month to the clamped date (Feb 28 + 1 month = Mar 28, not Mar 31), and uses `<= today`.

**L1.** `Tenra/Views/Components/Input/CategorySelectorView.swift:67` `.frame(width: 80)`;
`Tenra/Views/Components/Cards/CategoryChip.swift:52-55` `Text(category).font(AppTypography.bodyEmphasis).lineLimit(1)`
(18 pt semibold, no `minimumScaleFactor`). Longest presets: ru "Кафе и рестораны", uk "Комунальні послуги",
de "Dienstleistungen", es "Servicios públicos".

**T1.** `grep -rl <Type> TenraTests` counts: TransactionAddCoordinator 0, TransactionEditCoordinator 0,
SubscriptionNotificationScheduler 0, WeeklyDigestScheduler 0, PremiumManager 0, CSVImporter 0,
EntityMappingService 0 (CSV has round-trip tests).

## Evidence (not planned)

- **DP1** `docs/domains/deposits.md` ("Deposits converted BEFORE this fix have `conversionTimestamp == nil` ...
  stay corrupted until a one-shot recovery"); `grep -rn "conversionTimestamp == nil\|recover" Tenra` finds no recovery.
  Needs the affected user's data to design safely; start with a read-only diagnostic in the Experiments screen.
- **P1** `Tenra/Views/Transactions/TransactionEditCoordinator.swift:60-84` (computed, loops `allTransactions`),
  read in `TransactionEditView` body (`categories: coordinator.availableCategories`). Compute once in `init`.
- **P2** `Tenra/Views/Subscriptions/SubscriptionDetailView.swift:35-41`.
- **PW1** `Tenra/Services/Premium/PremiumManager.swift:61` (`isSubscriber = false`), first value set asynchronously in
  `observeCustomerInfo` (`:157-169`). Persist the last known entitlement in UserDefaults as the initial value.
- **S2** `Tenra/Info.plist` `NSUbiquitousContainers` → `NSUbiquitousContainerIsDocumentScopePublic = true`;
  backups are raw SQLite copies (`CloudBackupService.createBackup`).
- **S3** `Tenra/Services/Core/GoogleFaviconProvider.swift:22-26`, `LogoDevConfig.swift:49`.
- **DP2** `Tenra/Services/Deposits/DepositInterestService.swift:122,252` (`/ 365`).

## Checked and clean

- Translation mechanics: all 11 `Localizable.strings` have identical key sets; format specifiers match
  English for every key; no mixed positional/plain specifiers; no em dashes; `.stringsdict` and
  `AppShortcuts.strings` present everywhere. Values identical to English are legitimate cognates
  ("Transport", "Budget", "Description").
- No hardcoded Cyrillic or English UI strings outside `#Preview` and DEBUG screens.
- Paywall gates are consistent: accounts (4th), deposits, loans, voice tab, import tab, CSV import in
  Settings, multi-operation Siri phrases.
- Logging keeps user strings private by default; no persisted-level logs of descriptions or amounts found
  (debug-level insight logs print amounts publicly but are not persisted).
- Network endpoints are HTTPS only; no ATS exceptions.
- Voice type/date keywords cover 9 languages (ja/ko deferred by design, see docs/localization).

## Not audited

On-device visual pass (Dynamic Type accessibility sizes, long German strings on every screen),
real Instruments profiling (a July audit exists: docs/PERFORMANCE_AUDIT_2026_07.md), RevenueCat
dashboard paywall configuration, native-speaker review of translations, bank formats other than Kaspi.
